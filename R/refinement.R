#' Ecological Data Refinement Functions
#' 
#' Refine and enhance extracted ecological interaction data

#' Refine extracted records with additional context
#' @param db_conn Database connection
#' @param document_id Document ID
#' @param extraction_prompt_file Path to extraction prompt file (provides domain context)
#' @param refinement_prompt_file Path to custom refinement prompt file (optional, uses generic if not provided)
#' @param refinement_context_file Path to custom refinement context template file (optional)
#' @param schema_file Path to custom schema JSON file (optional)
#' @param model Provider and model in format "provider/model" (default: "anthropic/claude-sonnet-4-20250514")
#' @return List with refinement results
#' @export
refine_records <- function(db_conn = NULL, document_id,
                                extraction_prompt_file = NULL, refinement_prompt_file = NULL,
                                refinement_context_file = NULL,
                                schema_file = NULL,
                                model = "anthropic/claude-sonnet-4-20250514") {
  tryCatch({
    # Read document content from database (atomic - starts with DB)
    markdown_text <- get_document_content(document_id, db_conn)
    ocr_audit <- get_ocr_audit(document_id, db_conn)

    # Read existing records from database
    existing_records <- get_existing_records(document_id, db_conn)

    # Filter out human-edited and rejected records
    # We need to be careful here. We filter these out the LLM may just find them again but sligthly different
    # Filter out records that should not be refined
    # - human_edited: User manually edited, don't touch
    # - rejected: User rejected this record
    # - deleted_by_user: User flagged for deletion, don't re-extract or refine
    if (nrow(existing_records) > 0) {
      # Handle NA values in protection columns (treat NA as FALSE)
      is_human_edited <- !is.na(existing_records$human_edited) & existing_records$human_edited
      is_rejected <- !is.na(existing_records$rejected) & existing_records$rejected
      is_deleted <- if ("deleted_by_user" %in% names(existing_records)) {
        !is.na(existing_records$deleted_by_user) & existing_records$deleted_by_user
      } else {
        rep(FALSE, nrow(existing_records))
      }

      protected_count <- sum(is_human_edited | is_rejected | is_deleted)
      if (protected_count > 0) {
        message(glue::glue("Skipping {protected_count} protected records (human_edited, rejected, or deleted_by_user)"))
      }

      # Keep only records that are NOT human_edited, NOT rejected, and NOT deleted
      existing_records <- existing_records[!is_human_edited & !is_rejected & !is_deleted, ]
    }

    # Skip refinement if no records to refine (refinement only enhances, doesn't create)
    if (nrow(existing_records) == 0) {
      message("No records to refine (refinement only enhances existing records)")
      return(list(
        status = "skipped",
        records_refined = 0,
        document_id = document_id
      ))
    }

    # Load schema
    # Step 1: Identify schema file path
    schema_path <- load_config_file(schema_file, "schema.json", "extdata", return_content = FALSE)

    # Step 2: Convert raw text to R object using jsonlite
    schema_json <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
    schema_list <- jsonlite::fromJSON(schema_json, simplifyVector = FALSE)

    # Step 3: Convert to ellmer type schema
    schema <- ellmer::TypeJsonSchema(
      description = schema_list$description %||% "Interaction schema",
      json = schema_list
    )

    # Load extraction prompt (provides domain context for refinement)
    extraction_prompt <- get_extraction_prompt(extraction_prompt_file)

    # Load refinement prompt (generic rules - no injection needed)
    refinement_prompt <- get_refinement_prompt(refinement_prompt_file)

    # Load refinement context template
    refinement_context_template <- get_refinement_context_template(refinement_context_file)

    # Calculate prompt hash for model tracking
    prompt_hash <- digest::digest(paste(extraction_prompt, refinement_prompt, refinement_context_template, sep = "\n"), algo = "md5")

    # Build context for refinement
    # Include record_id so LLM can preserve it
    existing_context <- build_existing_records_context(existing_records, document_id, include_record_id = TRUE)

    # CLAUDE: We shouldn't need to test this. OCR audit must be available to reach this stage.
    audit_context <- if (is.null(ocr_audit)) {
      "No OCR audit available. No specific human edit audit context available."
    } else {
      paste("OCR Quality Analysis:", ocr_audit, "Human Edit Audit: No specific human edit audit context available.")
    }

    # Report inputs
    markdown_chars <- nchar(markdown_text)
    record_count <- nrow(existing_records)
    cat(glue::glue("Inputs loaded: OCR data ({markdown_chars} chars), OCR audit ({nchar(ocr_audit %||% '')} chars), {record_count} records, refinement prompt ({nchar(refinement_prompt)} chars, hash: {substring(prompt_hash, 1, 8)})"), "\n")

    # Initialize refinement chat
    cat("Calling", model, "for refinement\n")
    refine_chat <- ellmer::chat(
      name = model,
      system_prompt = refinement_prompt,  # System prompt is just the generic refinement instructions
      echo = "none",
      params = list(max_tokens = 8192)
    )

    # Build refinement context using glue to inject data
    document_content <- markdown_text  # Alias for template variable name
    refinement_context <- glue::glue(refinement_context_template,
      extraction_prompt = extraction_prompt,
      schema_json = schema_json,
      document_content = document_content,
      existing_records_context = existing_context,
      ocr_audit = audit_context
    )

    # Execute refinement with structured output
    refine_result <- refine_chat$chat_structured(refinement_context, type = schema)

    # Process result - chat_structured can return either a list or JSON string
    cat("Refinement completed\n")

    # Parse if it's a JSON string
    if (is.character(refine_result)) {
      refine_result <- jsonlite::fromJSON(refine_result, simplifyVector = FALSE)
    }

    # Now extract the records
    # ellmer automatically converts array of objects to data.frame
    if (is.list(refine_result) && "records" %in% names(refine_result)) {
      records_data <- refine_result$records
      if (is.data.frame(records_data) && nrow(records_data) > 0) {
        refined_df <- tibble::as_tibble(records_data)
      } else if (is.list(records_data) && length(records_data) > 0) {
        # Convert list of records to dataframe using jsonlite (handles nested structures better)
        refined_df <- tibble::as_tibble(jsonlite::fromJSON(jsonlite::toJSON(records_data, auto_unbox = TRUE)))

        # Fix any columns that came through as dataframes or weird structures
        for (col in names(refined_df)) {
          if (is.data.frame(refined_df[[col]]) || (is.list(refined_df[[col]]) && !is.null(names(refined_df[[col]])))) {
            # Extract actual values from nested structure
            refined_df[[col]] <- vapply(records_data, function(x) {
              val <- x[[col]]
              if (is.null(val) || (length(val) == 0)) {
                NA_character_
              } else if (is.list(val)) {
                # Keep lists as-is for arrays like all_supporting_source_sentences
                list(val)
              } else {
                as.character(val)
              }
            }, FUN.VALUE = if (col == "all_supporting_source_sentences") list(NULL) else character(1), USE.NAMES = FALSE)
          }
        }
      } else {
        refined_df <- tibble::tibble()
      }
    } else {
      # Might be the records dataframe directly
      refined_df <- tibble::as_tibble(refine_result)
    }

    # Process dataframe if valid
    if (is.data.frame(refined_df) && nrow(refined_df) > 0) {
      cat("\nRefinement output:\n")
      print(refined_df)
      cat("Rows refined:", nrow(refined_df), "rows\n")

      # Verify record_ids - LLM should have preserved them from existing records
      # No complex matching needed since LLM does the work
      if (nrow(existing_records) > 0) {
        refined_df <- match_and_restore_record_ids(refined_df, existing_records)
      }

      # Save refined records back to database
      # Pass the connection object directly (not the path) so it uses the same transaction
      save_records_to_db(
        db_path = db_conn,  # Now accepts connection object
        document_id = document_id,
        interactions_df = refined_df,
        metadata = list(
          model = model,
          prompt_hash = prompt_hash
        )
      )

      return(list(
        status = "completed",
        records_extracted = nrow(refined_df),
        document_id = document_id
      ))
    } else {
      message("No valid refined records returned")

      return(list(
        status = "completed",
        records_extracted = 0,
        document_id = document_id
      ))
    }
  }, error = function(e) {
    return(list(
      status = paste("Refinement failed:", e$message),
      records_extracted = 0,
      document_id = document_id
    ))
  })
}

#' Merge refined data back into original records (internal)
#' @param original_records Dataframe of original records
#' @param refined_records Dataframe of refined records
#' @return Dataframe with merged refinements
#' @keywords internal
merge_refinements <- function(original_records, refined_records) {
  if (nrow(refined_records) == 0) {
    return(original_records)
  }

  # Create a copy of original records to update
  updated_records <- original_records

  # Update each refined record
  for (i in 1:nrow(refined_records)) {
    refined_row <- refined_records[i, ]

    # Find matching original record by occurrence_id
    if ("occurrence_id" %in% names(refined_row) && "occurrence_id" %in% names(updated_records)) {
      match_idx <- which(updated_records$occurrence_id == refined_row$occurrence_id)

      if (length(match_idx) > 0) {
        # Update fields from refined data
        for (col_name in names(refined_row)) {
          if (col_name %in% names(updated_records)) {
            updated_records[match_idx[1], col_name] <- refined_row[[col_name]]
          }
        }
      }
    }
  }

  return(updated_records)
}

#' Verify and restore record_ids from LLM refinement
#' @param refined_records Dataframe of records from LLM refinement
#' @param existing_records Dataframe of existing records from database
#' @return Dataframe with record_ids verified (LLM should have preserved them)
#' @keywords internal
match_and_restore_record_ids <- function(refined_records, existing_records) {
  # LLM should have preserved record_id from the input
  # Just verify the field exists - no complex matching needed

  if (!"record_id" %in% names(refined_records)) {
    # If somehow record_id is missing, this is a problem
    warning("Refined records missing record_id field - refinement may have failed to preserve IDs")
    refined_records$record_id <- NA_character_
  }

  # Count how many records have valid record_ids (preserved from existing)
  valid_pattern <- "^[A-Za-z]+[0-9]+-o[0-9]+$"
  has_valid_id <- !is.na(refined_records$record_id) & grepl(valid_pattern, refined_records$record_id)

  preserved_count <- sum(has_valid_id)
  new_count <- sum(!has_valid_id)

  if (preserved_count > 0 && new_count > 0) {
    cat("Record IDs: ", preserved_count, " preserved, ", new_count, " new\n", sep = "")
  } else if (preserved_count > 0) {
    cat("Record IDs: All ", preserved_count, " preserved from existing records\n", sep = "")
  } else if (new_count > 0) {
    cat("Record IDs: All ", new_count, " are new records (will be generated)\n", sep = "")
  }

  return(refined_records)
}

#' Build context string for existing records
#' @param existing_records Dataframe of existing records
#' @param document_id Document ID for getting human edit summary
#' @return Character string with formatted context
