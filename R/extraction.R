#' Ecological Data Extraction Functions
#'
#' Extract structured ecological interaction data from OCR-processed documents

#' Extract records from markdown text
#'
#' Skip logic is handled by the workflow - this function always runs when called.
#' Uses deduplication to avoid creating duplicate records.
#'
#' @param document_id Optional document ID for context
#' @param db_conn Optional path to interaction database
#' @param document_content OCR-processed markdown content
#' @param extraction_prompt_file Path to custom extraction prompt file (optional)
#' @param extraction_context_file Path to custom extraction context template file (optional)
#' @param schema_file Path to custom schema JSON file (optional)
#' @param model Provider and model in format "provider/model" (default: "anthropic/claude-sonnet-4-5")
#' @param min_similarity Minimum similarity for deduplication (default: 0.9)
#' @param embedding_provider Provider for embeddings when using embedding method (default: "mistral")
#' @param similarity_method Method for deduplication similarity: "embedding", "jaccard", or "llm" (default: "llm")
#' @param reps Number of extraction passes (default: 1). Multiple passes
#'   increase recall by deduplicating each pass against accumulated results.
#' @param ... Additional arguments passed to extraction
#' @return List with extraction results
#' @keywords internal
extract_records <- function(document_id = NA,
                                 db_conn = NA,
                                 document_content = NA,
                                 extraction_prompt_file = NULL,
                                 extraction_context_file = NULL,
                                 schema_file = NULL,
                                 model = "anthropic/claude-sonnet-4-5",
                                 min_similarity = 0.9,
                                 embedding_provider = "openai",
                                 similarity_method = "llm",
                                 reps = 1,
                                 ...) {

  # Document content must be available either through the db or provided
  if(!is.na(document_id) && !inherits(db_conn, "logical")) {
    document_content <- get_document_content(document_id, db_conn)
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
      description = rlang::`%||%`(schema_list$description, "Record schema"),
      json = schema_list
    )

    # Load extraction prompt (custom or default)
    extraction_prompt <- get_extraction_prompt(extraction_prompt_file)
    extraction_prompt_hash <- digest::digest(extraction_prompt, algo = "md5")

    # Load extraction context template and inject variables with glue
    extraction_context_template <- get_extraction_context_template(extraction_context_file)
    extraction_context <- glue::glue(extraction_context_template, .na = "", .null = "")

    # Log input sizes
    cat(glue::glue(
      "Inputs loaded: Document content ({estimate_tokens(document_content)} tokens), extraction prompt (hash:{substring(extraction_prompt_hash, 1, 8)}, {estimate_tokens(extraction_prompt)} tokens)",
      .na = "0",
      .null = "0"
    ), "\n")

    # Track across reps — use env to avoid <<- scoping issues in tryCatch
    has_db <- !is.na(document_id) && !inherits(db_conn, "logical")
    track <- new.env(parent = emptyenv())
    track$models_used <- character(0)
    track$error_log <- NA_character_
    track$reasoning_text <- NULL
    track$status <- "completed"
    track$records_count <- 0
    reps <- as.integer(reps)

    for (rep in seq_len(reps)) {
      if (reps > 1) message(sprintf("  Extraction rep %d/%d...", rep, reps))

      # Per-rep tryCatch: a failed rep doesn't prevent others
      rep_result <- tryCatch({
        llm_result <- try_models_with_fallback(
          models = model,
          system_prompt = extraction_prompt,
          context = extraction_context,
          schema = schema,
          max_tokens = 64000,
          step_name = "Extraction"
        )

        extract_result <- llm_result$result
        track$models_used <- c(track$models_used, llm_result$model_used)
        track$error_log <- llm_result$error_log

        # Save reasoning on first rep only
        if (rep == 1) {
          if (is.list(extract_result) && "reasoning" %in% names(extract_result)) {
            track$reasoning_text <- extract_result$reasoning
          }
          if (has_db) {
            if (!is.null(track$reasoning_text) && nchar(track$reasoning_text) > 0) {
              save_reasoning_to_db(document_id, db_conn, track$reasoning_text, step = "extraction")
            } else {
              save_reasoning_to_db(document_id, db_conn, NA_character_, step = "extraction")
            }
          }
        }

        # Extract records from result
        if (is.list(extract_result) && "records" %in% names(extract_result)) {
          records_data <- extract_result$records

          if (is.data.frame(records_data) && nrow(records_data) > 0) {
            extraction_df <- tibble::as_tibble(records_data)
          } else if (is.list(records_data) && length(records_data) > 0) {
            records_data <- lapply(records_data, function(record) {
              lapply(record, function(val) if (is.null(val)) NA else val)
            })
            json_str <- jsonlite::toJSON(records_data, auto_unbox = TRUE, na = "null")
            extraction_df <- jsonlite::fromJSON(json_str, simplifyDataFrame = TRUE)
          } else {
            extraction_df <- tibble::tibble()
          }
        } else if (is.data.frame(extract_result)) {
          extraction_df <- tibble::as_tibble(extract_result)
        } else {
          extraction_df <- tibble::tibble()
        }

        # Dedup and save
        if (is.data.frame(extraction_df) && nrow(extraction_df) > 0) {
          extraction_df$fields_changed_count <- 0L

          if (has_db) {
            existing_records <- get_records(document_id, db_conn)
            if (is.null(existing_records)) existing_records <- tibble::tibble()

            dedup_result <- deduplicate_records(
              new_records = extraction_df,
              existing_records = existing_records,
              schema_list = schema_list,
              min_similarity = min_similarity,
              embedding_provider = embedding_provider,
              similarity_method = similarity_method,
              model = model
            )

            unique_records <- dedup_result$unique_records
            if (nrow(unique_records) > 0) {
              save_records_to_db(
                db_path = db_conn,
                document_id = document_id,
                interactions_df = unique_records,
                metadata = list(
                  model = track$models_used[length(track$models_used)],
                  prompt_hash = extraction_prompt_hash
                ),
                schema_list = schema_list,
                mode = "insert"
              )
            }
            track$records_count <- track$records_count + dedup_result$new_records_count
          } else {
            track$records_count <- nrow(extraction_df)
            extraction_df_no_db <- extraction_df
          }
        } else if (rep == 1) {
          # 0 records on first rep with no reasoning — flag as error
          if (is.null(track$reasoning_text) || is.na(track$reasoning_text) || nchar(track$reasoning_text) == 0) {
            track$status <- "Extraction failed: Model returned 0 records with no reasoning"
          }
        }

        "ok"
      }, error = function(e) {
        message(sprintf("  Extraction rep %d failed: %s", rep, e$message))
        if (rep == 1 && length(track$models_used) == 0) {
          # First rep failed — propagate so outer tryCatch handles it
          stop(e)
        }
        "failed"
      })
    }

    # Resolve tracked values
    model_used <- if (length(track$models_used) > 0) {
      jsonlite::toJSON(track$models_used, auto_unbox = TRUE)
    } else {
      NULL
    }
    error_log <- track$error_log
    status <- track$status
    records_count <- track$records_count
    reasoning_text <- track$reasoning_text

    # Save status and record count to DB (only if DB connection exists)
    if (!inherits(db_conn, "logical") && !is.na(document_id)) {
      status <- tryCatch({
        # Get current total record count for this document
        current_count <- DBI::dbGetQuery(db_conn,
          "SELECT COUNT(*) as count FROM records WHERE document_id = ?",
          params = list(document_id))$count[1]

        retry_db_operation({
          DBI::dbExecute(db_conn,
            "UPDATE documents SET extraction_status = ?, records_extracted = ? WHERE document_id = ?",
            params = list(status, current_count, document_id))
        })
        status
      }, error = function(e) {
        paste("Extraction failed: Could not save status -", e$message)
      })
    }

    # Post-write validation: verify reasoning and required fields in DB
    if (!inherits(db_conn, "logical") && !is.na(document_id) && status == "completed") {
      validation_errors <- character(0)

      # Check reasoning was stored (only if schema requires it)
      if ("reasoning" %in% schema_list$required) {
        doc_row <- DBI::dbGetQuery(db_conn,
          "SELECT extraction_reasoning FROM documents WHERE document_id = ?",
          params = list(document_id))
        if (nrow(doc_row) > 0 && (is.na(doc_row$extraction_reasoning[1]) || nchar(doc_row$extraction_reasoning[1]) == 0)) {
          validation_errors <- c(validation_errors, "extraction_reasoning is missing in DB")
        }
      }

      # Check non-nullable required fields on stored records.
      # Nullable fields ("type": ["string", "null"]) are allowed to be NA.
      stored_records <- get_records(document_id, db_conn)
      if (!is.null(stored_records) && nrow(stored_records) > 0) {
        record_props <- schema_list$properties$records$items$properties
        required_fields <- schema_list$properties$records$items$required
        if (!is.null(required_fields) && !is.null(record_props)) {
          for (field in intersect(required_fields, names(stored_records))) {
            field_type <- record_props[[field]]$type
            is_nullable <- is.list(field_type) && "null" %in% unlist(field_type)
            if (!is_nullable) {
              n_missing <- sum(is.na(stored_records[[field]]) | stored_records[[field]] == "")
              if (n_missing > 0) {
                validation_errors <- c(validation_errors,
                  sprintf("non-nullable field '%s' has %d missing value(s)", field, n_missing))
              }
            }
          }
        }
      }

      if (length(validation_errors) > 0) {
        warning("Post-write validation: ", paste(validation_errors, collapse = "; "))
      }
    }

    # Return appropriate structure based on DB connection
    if (exists("extraction_df_no_db")) {
      return(list(
        status = status,
        records_extracted = records_count,
        records = extraction_df_no_db,
        document_id = if (!is.na(document_id)) document_id else NA,
        raw_llm_response = extract_result,  # Include raw LLM response
        error_log = error_log,  # Include error log for audit
        model_used = model_used  # Model that succeeded
      ))
    } else {
      return(list(
        status = status,
        records_extracted = records_count,
        document_id = if (!is.na(document_id)) document_id else NA,
        raw_llm_response = extract_result,  # Include raw LLM response
        error_log = error_log,  # Include error log for audit
        model_used = model_used  # Model that succeeded
      ))
    }
  }, error = function(e) {
    status <- paste("Extraction failed:", e$message)

    # Try to save error status if DB exists
    if (!inherits(db_conn, "logical") && !is.na(document_id)) {
      tryCatch({
        retry_db_operation({
          DBI::dbExecute(db_conn,
            "UPDATE documents SET extraction_status = ? WHERE document_id = ?",
            params = list(status, document_id))
        })
      }, error = function(e2) {
        # Silently fail if can't save status
      })
    }

    return(list(
      status = status,
      records_extracted = 0,
      document_id = if (!is.na(document_id)) document_id else NA,
      raw_llm_response = NULL,  # No response on error
      error_log = e$error_log %||% NA_character_,
      model_used = model_used  # Preserve model even on error
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
