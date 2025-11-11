#' Document Audit - Extract Metadata and Review OCR Quality
#'
#' Performs comprehensive document analysis:
#' - Extracts publication metadata (title, authors, year, DOI, journal)
#' - Reviews OCR quality and identifies errors
#' - Saves results to documents table
#'
#' This is a schema-agnostic step that extracts universal publication metadata
#' and performs OCR quality checks, regardless of the domain-specific extraction
#' schema used in later steps.
#'
#' @param document_id Document ID in database
#' @param db_conn Database connection
#' @param force_reprocess If TRUE, re-run audit even if ocr_audit already exists (default: FALSE)
#' @param model LLM model for document audit (default: "anthropic/claude-sonnet-4-20250514")
#' @return List with status ("completed"/"skipped"/<error message>)
#' @export
audit_document <- function(document_id, db_conn, force_reprocess = FALSE, model = "anthropic/claude-sonnet-4-20250514") {

  # Check if audit already completed
  if (!force_reprocess) {
    existing_audit <- DBI::dbGetQuery(db_conn,
      "SELECT ocr_audit FROM documents WHERE id = ?",
      params = list(document_id))

    if (nrow(existing_audit) > 0 &&
        !is.na(existing_audit$ocr_audit[1]) &&
        nchar(existing_audit$ocr_audit[1]) > 0) {
      message("Document audit already completed for document ", document_id,
              ", skipping (force_reprocess=FALSE)")
      return(list(status = "skipped", document_id = document_id))
    }
  }

  tryCatch({
    # Read document content from database
    document_content <- get_document_content(document_id, db_conn)

    if (is.na(document_content) || is.null(document_content)) {
      return(list(status = "No document content found in database", document_id = document_id))
    }

    message("Performing document audit (metadata extraction + OCR quality review)...")

    # Load document audit schema and convert to native ellmer types
    schema_path <- system.file("extdata", "document_audit_schema.json", package = "ecoextract")
    if (!file.exists(schema_path)) {
      stop("Document audit schema not found at: ", schema_path)
    }

    schema_json <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
    schema <- json_schema_to_ellmer_type_document_audit(schema_path)

    # Load document audit prompt
    audit_prompt <- get_document_audit_prompt()

    # Load context template
    context_template <- get_document_audit_context()
    context <- glue::glue(context_template, .na = "", .null = "")

    message(glue::glue("Calling {model} for document audit"))

    # Initialize audit chat
    audit_chat <- ellmer::chat(
      name = model,
      system_prompt = audit_prompt,
      echo = "none"
    )

    # Execute audit with structured output
    audit_result <- audit_chat$chat_structured(context, type = schema)

    # Extract results (should have publication_metadata and ocr_audit)
    if (!is.list(audit_result)) {
      stop("Unexpected audit result format: not a list")
    }

    # Validate required fields exist
    if (!"publication_metadata" %in% names(audit_result)) {
      stop("Missing 'publication_metadata' in audit result. Available fields: ",
           paste(names(audit_result), collapse = ", "))
    }
    if (!"ocr_audit" %in% names(audit_result)) {
      stop("Missing 'ocr_audit' in audit result. Available fields: ",
           paste(names(audit_result), collapse = ", "))
    }

    pub_metadata <- audit_result$publication_metadata
    ocr_audit <- audit_result$ocr_audit

    # Save metadata and audit to database
    save_metadata_to_db(
      document_id = document_id,
      db_conn = db_conn,
      metadata = list(
        title = pub_metadata$title,
        first_author_lastname = pub_metadata$first_author_lastname,
        publication_year = pub_metadata$publication_year,
        doi = pub_metadata$doi,
        journal = pub_metadata$journal,
        ocr_audit = jsonlite::toJSON(ocr_audit, auto_unbox = TRUE)
      )
    )

    message("Document audit completed")
    message(glue::glue("  Metadata extracted: {pub_metadata$first_author_lastname %||% 'Unknown'} ({pub_metadata$publication_year %||% 'Year unknown'})"))

    return(list(status = "completed", document_id = document_id))
  }, error = function(e) {
    return(list(status = paste("Document audit failed:", e$message), document_id = document_id))
  })
}

#' Convert document audit JSON schema to native ellmer type specification
#'
#' Converts the document audit schema to ellmer's native type functions for
#' proper dataframe conversion
#'
#' @param schema_path Path to document audit JSON schema file
#' @return Ellmer type specification object
#' @keywords internal
json_schema_to_ellmer_type_document_audit <- function(schema_path) {
  # Read and parse JSON schema
  schema_json <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
  schema <- jsonlite::fromJSON(schema_json, simplifyVector = FALSE)

  # Build publication_metadata object
  pub_meta_props <- schema$properties$publication_metadata$properties
  pub_meta_fields <- list(
    title = ellmer::type_string(description = pub_meta_props$title$description, required = FALSE),
    first_author_lastname = ellmer::type_string(description = pub_meta_props$first_author_lastname$description, required = FALSE),
    publication_year = ellmer::type_integer(description = pub_meta_props$publication_year$description, required = FALSE),
    doi = ellmer::type_string(description = pub_meta_props$doi$description, required = FALSE),
    journal = ellmer::type_string(description = pub_meta_props$journal$description, required = FALSE)
  )

  # Build ocr_audit object
  ocr_audit_props <- schema$properties$ocr_audit$properties
  ocr_audit_fields <- list(
    audited_markdown = ellmer::type_string(description = ocr_audit_props$audited_markdown$description, required = FALSE),
    tables_reconstructed = ellmer::type_string(description = ocr_audit_props$tables_reconstructed$description, required = FALSE),
    errors_found = ellmer::type_string(description = ocr_audit_props$errors_found$description, required = FALSE)
  )

  # Build complete schema
  ellmer::type_object(
    publication_metadata = do.call(ellmer::type_object, pub_meta_fields),
    ocr_audit = do.call(ellmer::type_object, ocr_audit_fields)
  )
}

#' Get document audit prompt from package or custom location (internal)
#' @param prompt_file Optional path to custom document audit prompt file
#' @return Character string with document audit prompt
#' @keywords internal
get_document_audit_prompt <- function(prompt_file = NULL) {
  load_config_file(
    file_path = prompt_file,
    file_name = "document_audit_prompt.md",
    package_subdir = "prompts",
    return_content = TRUE
  )
}

#' Get document audit context template (internal)
#' @param context_file Optional path to custom context template file
#' @return Character string with context template
#' @keywords internal
get_document_audit_context <- function(context_file = NULL) {
  load_config_file(
    file_path = context_file,
    file_name = "document_audit_context.md",
    package_subdir = "prompts",
    return_content = TRUE
  )
}

#' @rdname audit_document
#' @export
audit_ocr <- function(document_id, db_conn, model = "anthropic/claude-sonnet-4-20250514") {
  .Deprecated("audit_document", package = "ecoextract",
    msg = "audit_ocr() is deprecated. Use audit_document() instead.")
  audit_document(document_id, db_conn, model)
}
