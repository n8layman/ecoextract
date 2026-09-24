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
#' @param metadata_schema_file Path to custom metadata schema JSON file (optional;
#'   its x-record-id-fields determine record IDs)
#' @param model Provider and model in format "provider/model" (default: "anthropic/claude-sonnet-5")
#' @param reasoning_effort Thinking effort (e.g. "low", "high"), or NULL
#'   (default) for thinking off. See \code{process_documents()}.
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
                                 metadata_schema_file = NULL,
                                 model = "anthropic/claude-sonnet-5",
                                 reasoning_effort = NULL,
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

  model_used <- NULL  # Initialize so error handler can always reference it

  # Track across reps — use env to avoid <<- scoping issues in tryCatch.
  # Created before tryCatch so the error handler can report token usage.
  track <- new.env(parent = emptyenv())
  track$models_used <- character(0)
  track$error_log <- NA_character_
  track$reasoning_text <- NULL
  track$status <- "completed"
  track$records_count <- 0
  track$usage <- NULL

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

    has_db <- !is.na(document_id) && !inherits(db_conn, "logical")
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
          step_name = "Extraction",
          reasoning_prompt = "Based on your analysis above, extract the structured records now.",
          reasoning_effort = reasoning_effort
        )

        extract_result <- llm_result$result
        track$models_used <- c(track$models_used, llm_result$model_used)
        track$error_log <- llm_result$error_log
        track$usage <- add_usage(track$usage, llm_result$usage)

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
              model = model,
              reasoning_effort = reasoning_effort
            )

            track$usage <- add_usage(track$usage, dedup_result$usage)
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
                mode = "insert",
                metadata_schema_file = metadata_schema_file
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
        err_msg <- e$message
        message(sprintf("  Extraction rep %d failed: %s", rep, err_msg))
        track$status <- paste("Extraction failed:", err_msg)
        track$usage <- add_usage(track$usage, e$usage)
        track$error_log <- if (is.na(track$error_log)) err_msg else paste(track$error_log, err_msg, sep = "; ")
        if (rep == 1 && length(track$models_used) == 0) {
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

      # Check reasoning was stored (always required — two-turn extraction always produces it)
      doc_row <- DBI::dbGetQuery(db_conn,
        "SELECT extraction_reasoning FROM documents WHERE document_id = ?",
        params = list(document_id))
      if (nrow(doc_row) > 0 && (is.na(doc_row$extraction_reasoning[1]) || nchar(doc_row$extraction_reasoning[1]) == 0)) {
        validation_errors <- c(validation_errors, "extraction_reasoning is missing in DB")
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
        model_used = model_used,  # Model that succeeded
        usage = track$usage  # Token usage across reps, retries, and deduplication
      ))
    } else {
      return(list(
        status = status,
        records_extracted = records_count,
        document_id = if (!is.na(document_id)) document_id else NA,
        raw_llm_response = extract_result,  # Include raw LLM response
        error_log = error_log,  # Include error log for audit
        model_used = model_used,  # Model that succeeded
        usage = track$usage  # Token usage across reps, retries, and deduplication
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
      model_used = model_used,  # Preserve model even on error
      usage = track$usage
    ))
  })
}

#' Generate record IDs (internal)
#' @param prefix Record ID prefix for the document, from \code{build_record_id_prefix()}
#' @param sequence_number Sequence number(s) of records within the document
#' @return Character vector of record IDs
#' @keywords internal
generate_record_id <- function(prefix, sequence_number = 1) {
  paste0(prefix, "_r", sequence_number)
}

#' Build a record ID prefix from a document's identifier values (internal)
#'
#' Joins the values of the metadata fields named in \code{x-record-id-fields},
#' each stripped to letters and digits, followed by the replicate number.
#' Missing or empty values become "Unknown". For the default metadata schema
#' this gives "Author_Year_1".
#'
#' @param id_values List of identifier values, in \code{x-record-id-fields} order
#' @return Character record ID prefix
#' @keywords internal
build_record_id_prefix <- function(id_values) {
  parts <- purrr::map_chr(id_values, function(value) {
    cleaned <- if (is.null(value) || is.na(value)) "" else {
      stringr::str_replace_all(as.character(value), "[^A-Za-z0-9]", "")
    }
    if (nchar(cleaned) == 0) "Unknown" else cleaned
  })
  # Replicate number is always 1 for now (see issue #141)
  paste0(paste(parts, collapse = "_"), "_1")
}

#' Get the record ID prefix for a document in the database (internal)
#'
#' Looks up the document's values for the fields named in the metadata
#' schema's \code{x-record-id-fields}. \code{file_name} is used without its
#' extension.
#'
#' @param con Database connection
#' @param document_id Document ID
#' @param metadata_schema_file Path to custom metadata schema JSON file (optional)
#' @return Character record ID prefix
#' @keywords internal
get_record_id_prefix <- function(con, document_id, metadata_schema_file = NULL) {
  id_fields <- get_record_id_fields(load_metadata_schema(metadata_schema_file))
  doc <- DBI::dbGetQuery(con,
    paste("SELECT", paste(DBI::dbQuoteIdentifier(con, id_fields), collapse = ", "),
          "FROM documents WHERE document_id = ?"),
    params = list(document_id))
  if ("file_name" %in% id_fields) {
    doc$file_name <- tools::file_path_sans_ext(doc$file_name)
  }
  build_record_id_prefix(as.list(doc[1, id_fields, drop = FALSE]))
}
