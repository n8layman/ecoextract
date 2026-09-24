#' Extract Document Metadata
#'
#' Extracts document-level metadata from OCR-processed documents and saves it
#' to the documents table. The fields come from the metadata schema, loaded
#' with the usual config priority (explicit file, then
#' \code{ecoextract/metadata_schema.json}, then the package default of
#' bibliographic fields for journal articles).
#' Skip logic is handled by the workflow - this function always runs when called.
#'
#' @param document_id Document ID in database
#' @param db_conn Database connection
#' @param force_reprocess Ignored (kept for backward compatibility). Skip logic handled by workflow.
#' @param model LLM model for metadata extraction (default: "anthropic/claude-sonnet-5")
#' @param metadata_schema_file Path to custom metadata schema JSON file (optional)
#' @param metadata_prompt_file Path to custom metadata prompt file (optional)
#' @return List with status ("completed"/<error message>), document_id, and
#'   usage (token usage across all attempts, NULL if no LLM call was made)
#' @keywords internal
extract_metadata <- function(document_id, db_conn, force_reprocess = TRUE,
                             model = "anthropic/claude-sonnet-5",
                             metadata_schema_file = NULL,
                             metadata_prompt_file = NULL) {

  # Handle database connection - accept either connection object or path
  if (!inherits(db_conn, "DBIConnection")) {
    # Path string - initialize if needed, then connect
    if (!file.exists(db_conn)) {
      cat("Initializing new database:", db_conn, "\n")
      init_ecoextract_database(db_conn, metadata_schema_file = metadata_schema_file)
    }
    db_conn <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    configure_sqlite_connection(db_conn)
    on.exit(DBI::dbDisconnect(db_conn), add = TRUE)
  }

  # Get document from database
  doc <- DBI::dbGetQuery(db_conn,
    "SELECT * FROM documents WHERE document_id = ?",
    params = list(document_id))

  # Run metadata extraction
  usage <- NULL
  status <- tryCatch({
    # Read document content from database
    document_content <- doc$document_content

    if (is.na(document_content) || is.null(document_content)) {
      "Metadata extraction failed: No document content found in database"
    } else {

    message("Extracting document metadata...")

    # Load metadata schema (custom or default) and convert to ellmer TypeJsonSchema
    schema_json <- load_config_file(metadata_schema_file, "metadata_schema.json", "extdata", return_content = TRUE)
    schema_list <- jsonlite::fromJSON(schema_json, simplifyVector = FALSE)
    metadata_fields <- get_metadata_fields(schema_list)
    schema <- ellmer::TypeJsonSchema(
      description = rlang::`%||%`(schema_list$description, "Document metadata schema"),
      json = schema_list
    )

    # Load metadata extraction prompt
    metadata_prompt <- get_metadata_prompt(metadata_prompt_file)

    # Load context template
    context_template <- get_metadata_context()
    context <- glue::glue(context_template, .na = "", .null = "")

    # Execute metadata extraction with model fallback
    llm_result <- try_models_with_fallback(
      models = model,
      system_prompt = metadata_prompt,
      context = context,
      schema = schema,
      max_tokens = 64000,
      step_name = "Metadata extraction"
    )

    metadata_result <- llm_result$result
    model_used <- llm_result$model_used
    error_log <- llm_result$error_log
    usage <- llm_result$usage

    # Extract results
    if (!is.list(metadata_result)) {
      stop("Unexpected metadata result format: not a list")
    }

    # Validate required fields exist
    metadata_key <- get_metadata_key(schema_list)
    if (!metadata_key %in% names(metadata_result)) {
      stop("Missing '", metadata_key, "' in result. Available fields: ",
           paste(names(metadata_result), collapse = ", "))
    }

    doc_metadata <- metadata_result[[metadata_key]]

    # Serialize array and object fields to JSON strings for storage
    metadata <- purrr::imap(metadata_fields, function(field_spec, field) {
      value <- doc_metadata[[field]]
      if (is.null(value) || length(value) == 0) return(NA)
      if (json_property_type(field_spec) %in% c("array", "object")) {
        as.character(jsonlite::toJSON(value, auto_unbox = TRUE))
      } else {
        value
      }
    })

    save_metadata_to_db(
      document_id = document_id,
      db_conn = db_conn,
      metadata = metadata,
      metadata_llm_model = model_used,
      metadata_log = error_log
    )

      # Log metadata extracted to console for user. Arrays are summarized by length.
      message("Metadata extraction completed:")
      purrr::iwalk(metadata_fields, function(field_spec, field) {
        value <- doc_metadata[[field]]
        shown <- if (is.null(value) || length(value) == 0) {
          "<empty>"
        } else if (json_property_type(field_spec) %in% c("array", "object")) {
          paste(length(value), "items")
        } else {
          value
        }
        message(glue::glue("  {field}: {shown}"))
      })

      "completed"
    }
  }, error = function(e) {
    usage <<- e$usage %||% usage
    paste("Metadata extraction failed:", e$message)
  })

  return(list(status = status, document_id = document_id, usage = usage))
}

#' Load the metadata JSON schema (internal)
#'
#' Uses the config priority order: an explicit file, then
#' \code{ecoextract/metadata_schema.json} in the project directory, then the
#' package default.
#'
#' @param schema_file Path to custom metadata schema JSON file (optional)
#' @return Parsed metadata JSON schema as a list
#' @keywords internal
load_metadata_schema <- function(schema_file = NULL) {
  schema_path <- load_config_file(schema_file, "metadata_schema.json", "extdata", return_content = FALSE)
  jsonlite::fromJSON(schema_path, simplifyVector = FALSE)
}

#' Get the name of a metadata schema's metadata object (internal)
#'
#' The metadata schema wraps its fields in a single object under
#' \code{properties}. The package default calls it
#' \code{publication_metadata}; custom schemas can use any name.
#'
#' @param schema_list Parsed metadata JSON schema
#' @return Character name of the metadata object
#' @keywords internal
get_metadata_key <- function(schema_list) {
  key <- names(schema_list$properties)
  if (length(key) != 1) {
    stop("Metadata schema must contain exactly one object under 'properties' ",
         "(e.g. 'publication_metadata'), found: ",
         if (length(key) == 0) "none" else paste(key, collapse = ", "))
  }
  key
}

#' Get field definitions from a metadata schema (internal)
#' @param schema_list Parsed metadata JSON schema
#' @return Named list of field definitions
#' @keywords internal
get_metadata_fields <- function(schema_list) {
  key <- get_metadata_key(schema_list)
  fields <- schema_list$properties[[key]]$properties
  if (is.null(fields)) {
    stop("Metadata schema must contain 'properties.", key, ".properties'")
  }
  fields
}

#' Get the metadata fields that form record IDs (internal)
#'
#' Reads \code{x-record-id-fields} from the metadata schema's metadata
#' object (see \code{get_metadata_key()}). Each entry must be a metadata field,
#' \code{document_id}, or \code{file_name}.
#'
#' @param schema_list Parsed metadata JSON schema
#' @return Character vector of field names
#' @keywords internal
get_record_id_fields <- function(schema_list) {
  key <- get_metadata_key(schema_list)
  id_fields <- unlist(schema_list$properties[[key]][["x-record-id-fields"]])
  if (length(id_fields) == 0) {
    stop(
      "Metadata schema is missing 'x-record-id-fields' array.\n",
      "This field names the metadata fields that form record IDs.\n",
      "Add to your metadata schema at properties > ", key, ":\n\n",
      '  "x-record-id-fields": ["field1", "field2"]'
    )
  }
  allowed <- c(names(get_metadata_fields(schema_list)), "document_id", "file_name")
  unknown <- setdiff(id_fields, allowed)
  if (length(unknown) > 0) {
    stop("x-record-id-fields entries must be metadata fields, document_id, or file_name. ",
         "Unknown: ", paste(unknown, collapse = ", "))
  }
  id_fields
}

#' Get metadata prompt from package or custom location (internal)
#' @param prompt_file Optional path to custom metadata prompt file
#' @return Character string with metadata prompt
#' @keywords internal
get_metadata_prompt <- function(prompt_file = NULL) {
  load_config_file(
    file_path = prompt_file,
    file_name = "metadata_prompt.md",
    package_subdir = "prompts",
    return_content = TRUE
  )
}

#' Get metadata context template (internal)
#' @param context_file Optional path to custom context template file
#' @return Character string with context template
#' @keywords internal
get_metadata_context <- function(context_file = NULL) {
  load_config_file(
    file_path = context_file,
    file_name = "metadata_context.md",
    package_subdir = "prompts",
    return_content = TRUE
  )
}
