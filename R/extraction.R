#' Ecological Data Extraction Functions
#'
#' Extract structured ecological interaction data from OCR-processed documents

#' Extract records from markdown text
#' @param document_id Optional document ID for context
#' @param db_conn Optional path to interaction database
#' @param document_content OCR-processed markdown content
#' @param force_reprocess If TRUE, re-run extraction even if records already exist (default: FALSE)
#' @param extraction_prompt_file Path to custom extraction prompt file (optional)
#' @param extraction_context_file Path to custom extraction context template file (optional)
#' @param schema_file Path to custom schema JSON file (optional)
#' @param model Provider and model in format "provider/model" (default: "anthropic/claude-sonnet-4-5")
#' @param ... Additional arguments passed to extraction
#' @return List with extraction results
#' @keywords internal
extract_records <- function(document_id = NA,
                                 db_conn = NA,
                                 document_content = NA,
                                 force_reprocess = FALSE,
                                 extraction_prompt_file = NULL,
                                 extraction_context_file = NULL,
                                 schema_file = NULL,
                                 model = "anthropic/claude-sonnet-4-5",
                                 ...) {

  # Document content must be available either through the db or provided
  existing_records <- tibble::tibble()
  if(!is.na(document_id) && !inherits(db_conn, "logical")) {
    document_content <- get_document_content(document_id, db_conn)

    # Always get existing records to provide as context (extraction looks for NEW records)
    existing_records <- get_records(document_id, db_conn)
    if (is.null(existing_records)) {
      existing_records <- tibble::tibble()
    }
  }
  if(is.na(document_content)) {
    stop("ERROR message please provide either the id of a document in the database or markdown OCR document content.")
  }

  tryCatch({
    # Load schema JSON and convert to ellmer TypeJsonSchema
    schema_path <- load_config_file(schema_file, "schema.json", "extdata", return_content = FALSE)
    schema_json <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
    schema_list <- jsonlite::fromJSON(schema_json, simplifyVector = FALSE)
    schema <- ellmer::TypeJsonSchema(
      description = schema_list$description %||% "Record schema",
      json = schema_list
    )

    # Load extraction prompt (custom or default)
    extraction_prompt <- get_extraction_prompt(extraction_prompt_file)
    extraction_prompt_hash <- digest::digest(extraction_prompt, algo = "md5")

    # Build existing records context (so extraction can avoid duplicates)
    # Don't include record_id - extraction doesn't generate IDs, system does
    existing_records_context <- build_existing_records_context(existing_records, document_id, include_record_id = FALSE)

    # Load extraction context template and inject variables with glue
    extraction_context_template <- get_extraction_context_template(extraction_context_file)
    extraction_context <- glue::glue(extraction_context_template, .na = "", .null = "")

    # Log input sizes
    cat(glue::glue(
      "Inputs loaded: Document content ({estimate_tokens(document_content)} tokens), {nrow(existing_records)} existing records, extraction prompt (hash:{substring(extraction_prompt_hash, 1, 8)}, {estimate_tokens(extraction_prompt)} tokens)",
      .na = "0",
      .null = "0"
    ), "\n")

    # Initialize extraction chat
    cat("Calling", model, "for extraction\n")
    extract_chat <- ellmer::chat(
      name = model,
      system_prompt = extraction_prompt,
      echo = "none",
      params = list(max_tokens = 16384)
    )

    # Execute extraction with structured output
    # Using native ellmer types, arrays of objects are automatically converted to dataframes
    extract_result <- extract_chat$chat_structured(extraction_context, type = schema)

    cat("Extraction completed\n")

    # Extract and save reasoning
    if (is.list(extract_result) && "reasoning" %in% names(extract_result)) {
      reasoning_text <- extract_result$reasoning
      if (!is.na(document_id) && !inherits(db_conn, "logical") && !is.null(reasoning_text) && nchar(reasoning_text) > 0) {
        save_reasoning_to_db(document_id, db_conn, reasoning_text, step = "extraction")
      }
    }

    # Extract records from result
    if (is.list(extract_result) && "records" %in% names(extract_result)) {
      records_data <- extract_result$records

      # Handle different formats returned by ellmer
      if (is.data.frame(records_data) && nrow(records_data) > 0) {
        # Already a dataframe
        extraction_df <- tibble::as_tibble(records_data)
      } else if (is.list(records_data) && length(records_data) > 0) {
        # List of lists - use jsonlite to preserve array structure
        # Convert to JSON and back to ensure arrays stay as list columns
        json_str <- jsonlite::toJSON(records_data, auto_unbox = TRUE)
        extraction_df <- jsonlite::fromJSON(json_str, simplifyDataFrame = TRUE)
      } else {
        extraction_df <- tibble::tibble()
      }
    } else if (is.data.frame(extract_result)) {
      # Direct dataframe result
      extraction_df <- tibble::as_tibble(extract_result)
    } else {
      extraction_df <- tibble::tibble()
    }

    # Process dataframe if valid
    if (is.data.frame(extraction_df) && nrow(extraction_df) > 0) {
      # Set fields_changed_count to 0 for new extractions
      extraction_df$fields_changed_count <- 0L

      # Save to database (atomic step)
      if (!is.na(document_id) && !inherits(db_conn, "logical")) {
        save_records_to_db(
          db_path = db_conn,  # Pass connection object, not path
          document_id = document_id,
          interactions_df = extraction_df,
          metadata = list(
            model = model,
            prompt_hash = extraction_prompt_hash
          ),
          schema_list = schema_list  # Pass schema for array normalization
        )

        status <- "completed"
        records_count <- nrow(extraction_df)
      } else {
        # No DB connection
        status <- "Extraction failed: No database connection"
        records_count <- nrow(extraction_df)
        extraction_df_no_db <- extraction_df  # Save for return
      }
    } else {
      status <- "completed"
      records_count <- 0
    }

    # Save status and record count to DB (only if DB connection exists)
    if (!inherits(db_conn, "logical") && !is.na(document_id)) {
      status <- tryCatch({
        # Get current total record count for this document
        current_count <- DBI::dbGetQuery(db_conn,
          "SELECT COUNT(*) as count FROM records WHERE document_id = ?",
          params = list(document_id))$count[1]

        DBI::dbExecute(db_conn,
          "UPDATE documents SET extraction_status = ?, records_extracted = ? WHERE document_id = ?",
          params = list(status, current_count, document_id))
        status
      }, error = function(e) {
        paste("Extraction failed: Could not save status -", e$message)
      })
    }

    # Return appropriate structure based on DB connection
    if (exists("extraction_df_no_db")) {
      return(list(
        status = status,
        records_extracted = records_count,
        records = extraction_df_no_db,
        document_id = if (!is.na(document_id)) document_id else NA
      ))
    } else {
      return(list(
        status = status,
        records_extracted = records_count,
        document_id = if (!is.na(document_id)) document_id else NA
      ))
    }
  }, error = function(e) {
    status <- paste("Extraction failed:", e$message)

    # Try to save error status if DB exists
    if (!inherits(db_conn, "logical") && !is.na(document_id)) {
      tryCatch({
        DBI::dbExecute(db_conn,
          "UPDATE documents SET extraction_status = ? WHERE document_id = ?",
          params = list(status, document_id))
      }, error = function(e2) {
        # Silently fail if can't save status
      })
    }

    return(list(
      status = status,
      records_extracted = 0,
      document_id = if (!is.na(document_id)) document_id else NA
    ))
  })
}

# CLAUDE: This is generic enough. All papers will have author and pub year. And the point of this package is to extract data from pubs. Schemas might be different but this will be the same
#' Generate record ID for a record (internal)
#' @param author_lastname Author surname
#' @param publication_year Publication year
#' @param sequence_number Sequence number for this record
#' @return Character record ID
#' @keywords internal
generate_record_id <- function(author_lastname, publication_year, sequence_number = 1) {
  # Clean author name
  clean_author <- stringr::str_replace_all(author_lastname, "[^A-Za-z]", "")
  if (nchar(clean_author) == 0) clean_author <- "Author"

  # Create record ID: Author_Year_Paper_Record
  # Paper number (1) differentiates multiple papers from same author/year
  # Record number is the sequence within that paper
  paste0(clean_author, "_", publication_year, "_1_r", sequence_number)
}
