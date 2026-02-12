#' Extract Publication Metadata
#'
#' Extracts publication metadata from OCR-processed scientific documents:
#' - Title, authors, publication year, DOI, journal
#' - Saves results to documents table
#'
#' This is a schema-agnostic step that extracts universal publication metadata
#' regardless of the domain-specific extraction schema used in later steps.
#' Skip logic is handled by the workflow - this function always runs when called.
#'
#' @param document_id Document ID in database
#' @param db_conn Database connection
#' @param force_reprocess Ignored (kept for backward compatibility). Skip logic handled by workflow.
#' @param model LLM model for metadata extraction (default: "anthropic/claude-sonnet-4-5")
#' @return List with status ("completed"/<error message>) and document_id
#' @keywords internal
extract_metadata <- function(document_id, db_conn, force_reprocess = TRUE, model = "anthropic/claude-sonnet-4-5") {

  # Handle database connection - accept either connection object or path
  if (!inherits(db_conn, "DBIConnection")) {
    # Path string - initialize if needed, then connect
    if (!file.exists(db_conn)) {
      cat("Initializing new database:", db_conn, "\n")
      init_ecoextract_database(db_conn)
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
  status <- tryCatch({
    # Read document content from database
    document_content <- doc$document_content

    if (is.na(document_content) || is.null(document_content)) {
      "Metadata extraction failed: No document content found in database"
    } else {

    message("Extracting publication metadata...")

    # Load metadata schema and convert to native ellmer types
    schema_path <- system.file("extdata", "metadata_schema.json", package = "ecoextract")
    if (!file.exists(schema_path)) {
      stop("Metadata schema not found at: ", schema_path)
    }

    schema_json <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
    schema <- json_schema_to_ellmer_type_metadata(schema_path)

    # Load metadata extraction prompt
    metadata_prompt <- get_metadata_prompt()

    # Load context template
    context_template <- get_metadata_context()
    context <- glue::glue(context_template, .na = "", .null = "")

    # Execute metadata extraction with model fallback
    llm_result <- try_models_with_fallback(
      models = model,
      system_prompt = metadata_prompt,
      context = context,
      schema = schema,
      max_tokens = 16384,
      step_name = "Metadata extraction"
    )

    metadata_result <- llm_result$result
    model_used <- llm_result$model_used
    error_log <- llm_result$error_log

    # Extract results
    if (!is.list(metadata_result)) {
      stop("Unexpected metadata result format: not a list")
    }

    # Validate required fields exist
    if (!"publication_metadata" %in% names(metadata_result)) {
      stop("Missing 'publication_metadata' in result. Available fields: ",
           paste(names(metadata_result), collapse = ", "))
    }

    pub_metadata <- metadata_result$publication_metadata

    # Convert authors array to JSON string for storage
    authors_json <- if (!is.null(pub_metadata$authors) && length(pub_metadata$authors) > 0) {
      jsonlite::toJSON(pub_metadata$authors, auto_unbox = FALSE)
    } else {
      NA_character_
    }

    # Convert bibliography array to JSON string for storage
    references_json <- if (!is.null(pub_metadata$bibliography) && length(pub_metadata$bibliography) > 0) {
      jsonlite::toJSON(pub_metadata$bibliography, auto_unbox = FALSE)
    } else {
      NA_character_
    }

    # Save metadata to database
    save_metadata_to_db(
      document_id = document_id,
      db_conn = db_conn,
      metadata = list(
        title = pub_metadata$title,
        first_author_lastname = pub_metadata$first_author_lastname,
        authors = authors_json,
        publication_year = pub_metadata$publication_year,
        doi = pub_metadata$doi,
        journal = pub_metadata$journal,
        volume = pub_metadata$volume,
        issue = pub_metadata$issue,
        pages = pub_metadata$pages,
        issn = pub_metadata$issn,
        publisher = pub_metadata$publisher,
        bibliography = references_json,
        language = pub_metadata$language
      ),
      metadata_llm_model = model_used,
      metadata_log = error_log
    )

      # Log metadata extracted to console for user.
      message("Metadata extraction completed:")
      message(glue::glue("  title: {rlang::`%||%`(pub_metadata$title, '<empty>')}"))
      message(glue::glue("  first_author_lastname: {rlang::`%||%`(pub_metadata$first_author_lastname, '<empty>')}"))
      message(glue::glue("  authors: {if(!is.null(pub_metadata$authors)) paste(pub_metadata$authors, collapse=', ') else '<empty>'}"))
      message(glue::glue("  publication_year: {rlang::`%||%`(pub_metadata$publication_year, '<empty>')}"))
      message(glue::glue("  doi: {rlang::`%||%`(pub_metadata$doi, '<empty>')}"))
      message(glue::glue("  journal: {rlang::`%||%`(pub_metadata$journal, '<empty>')}"))
      message(glue::glue("  volume: {rlang::`%||%`(pub_metadata$volume, '<empty>')}"))
      message(glue::glue("  issue: {rlang::`%||%`(pub_metadata$issue, '<empty>')}"))
      message(glue::glue("  pages: {rlang::`%||%`(pub_metadata$pages, '<empty>')}"))
      message(glue::glue("  issn: {rlang::`%||%`(pub_metadata$issn, '<empty>')}"))
      message(glue::glue("  publisher: {rlang::`%||%`(pub_metadata$publisher, '<empty>')}"))
      message(glue::glue("  language: {rlang::`%||%`(pub_metadata$language, '<empty>')}"))
      message(glue::glue("  references: {if(!is.null(pub_metadata$bibliography)) length(pub_metadata$bibliography) else 0} citations"))

      "completed"
    }
  }, error = function(e) {
    paste("Metadata extraction failed:", e$message)
  })

  return(list(status = status, document_id = document_id))
}

#' Convert metadata JSON schema to native ellmer type specification
#'
#' Converts the metadata schema to ellmer's native type functions for
#' proper dataframe conversion
#'
#' @param schema_path Path to metadata JSON schema file
#' @return Ellmer type specification object
#' @keywords internal
json_schema_to_ellmer_type_metadata <- function(schema_path) {
  # Read and parse JSON schema
  schema_json <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
  schema <- jsonlite::fromJSON(schema_json, simplifyVector = FALSE)

  # Build publication_metadata object
  pub_meta_props <- schema$properties$publication_metadata$properties
  pub_meta_fields <- list(
    title = ellmer::type_string(description = pub_meta_props$title$description, required = FALSE),
    first_author_lastname = ellmer::type_string(description = pub_meta_props$first_author_lastname$description, required = FALSE),
    authors = ellmer::type_array(
      items = ellmer::type_string(),
      description = pub_meta_props$authors$description,
      required = FALSE
    ),
    publication_year = ellmer::type_integer(description = pub_meta_props$publication_year$description, required = FALSE),
    doi = ellmer::type_string(description = pub_meta_props$doi$description, required = FALSE),
    journal = ellmer::type_string(description = pub_meta_props$journal$description, required = FALSE),
    volume = ellmer::type_string(description = pub_meta_props$volume$description, required = FALSE),
    issue = ellmer::type_string(description = pub_meta_props$issue$description, required = FALSE),
    pages = ellmer::type_string(description = pub_meta_props$pages$description, required = FALSE),
    issn = ellmer::type_string(description = pub_meta_props$issn$description, required = FALSE),
    publisher = ellmer::type_string(description = pub_meta_props$publisher$description, required = FALSE),
    bibliography = ellmer::type_array(
      items = ellmer::type_string(),
      description = pub_meta_props$bibliography$description,
      required = FALSE
    ),
    language = ellmer::type_string(description = pub_meta_props$language$description, required = FALSE)
  )

  # Build complete schema with publication_metadata as optional
  pub_meta_type <- do.call(ellmer::type_object, pub_meta_fields)
  pub_meta_type@required <- FALSE

  ellmer::type_object(
    publication_metadata = pub_meta_type
  )
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

#' Limit document content to first N pages
#' @param content Full document content (markdown from OCR)
#' @param n Number of pages to keep (default: 3)
#' @return Content limited to first n pages
#' @keywords internal
limit_to_first_n_pages <- function(content, n = 3) {
  # Split on page markers (format: "--- PAGE N ---")
  # Note: Markers appear AFTER each page, so "--- PAGE 1 ---" comes after page 1 content
  page_pattern <- "--- PAGE \\d+ ---"
  page_positions <- gregexpr(page_pattern, content)[[1]]

  # If no page markers found, document has only 1 page
  if (page_positions[1] == -1) {
    return(content)
  }

  # Number of pages = number of markers (since each page now has a marker after it)
  num_pages <- length(page_positions)

  # If document has n or fewer pages, return all content
  if (num_pages <= n) {
    return(content)
  }

  # To get first n pages, find the marker after page n and cut there
  # e.g., for n=3, find "--- PAGE 3 ---" and include everything up to end of that marker
  end_pos <- page_positions[n] + attr(page_positions, "match.length")[n]
  substr(content, 1, end_pos)
}
