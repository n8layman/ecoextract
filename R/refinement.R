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
    # CLAUDE: how should we deal with this simply? Tell me the plan do not automatically execute the fix without approval.
    # This might have to be a part of the refinement prompt. Strong language not to alter rows with human_edited = TRUE or rejected = TRUE.
    # Maybe a good place to insert a test. Did those lines get changed? If so error out rather than refine.
    if (nrow(existing_records) > 0) {
      protected_count <- sum(existing_records$human_edited | existing_records$rejected, na.rm = TRUE)
      if (protected_count > 0) {
        message(glue::glue("Skipping {protected_count} protected records (human_edited or rejected)"))
      }
      existing_records <- existing_records[!existing_records$human_edited & !existing_records$rejected, ]
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
    existing_context <- build_existing_records_context(existing_records, document_id)

    # CLAUDE: We shouldn't need to test this. OCR audit must be available to reach this stage.
    audit_context <- if (is.null(ocr_audit)) {
      "No OCR audit available. No specific human edit audit context available."
    } else {
      paste("OCR Quality Analysis:", ocr_audit, "Human Edit Audit: No specific human edit audit context available.")
    }

    # Report inputs
    markdown_chars <- nchar(markdown_text)
    record_count <- nrow(existing_records)
    cat("Inputs loaded: OCR data (", markdown_chars, " chars), OCR audit (", nchar(ocr_audit %||% ""), " chars), ", record_count, " records, refinement prompt (", nchar(refinement_prompt), " chars, hash:", substring(prompt_hash, 1, 8), ")\n")

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

      # Save refined records back to database
      save_records_to_db(
        db_path = db_conn@dbname,
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

#' Build context string for existing records
#' @param existing_records Dataframe of existing records
#' @param document_id Document ID for getting human edit summary
#' @return Character string with formatted context
build_existing_records_context <- function(existing_records, document_id = NULL) {
  if (is.null(existing_records) || !is.data.frame(existing_records) || nrow(existing_records) == 0) {
    return("No records have been extracted from this document yet.")
  }

  # Exclude metadata columns from display
  metadata_cols <- c("id", "document_id", "extraction_timestamp",
                     "llm_model_version", "prompt_hash", "flagged_for_review",
                     "review_reason", "human_edited", "rejected")
  data_cols <- setdiff(names(existing_records), metadata_cols)

  # Build context as simple JSON representation
  context_lines <- c("Existing records:", "")

  for (i in seq_len(nrow(existing_records))) {
    row <- existing_records[i, data_cols, drop = FALSE]

    # Convert row to simple key-value format
    record_parts <- character(0)
    for (col in data_cols) {
      val <- row[[col]]
      if (is.list(val)) val <- jsonlite::toJSON(val, auto_unbox = TRUE)
      if (!is.na(val) && val != "") {
        record_parts <- c(record_parts, paste0(col, ": ", val))
      }
    }

    context_line <- paste0("- ", paste(record_parts, collapse = ", "))
    context_lines <- c(context_lines, context_line)
  }

  return(paste(context_lines, collapse = "\n"))
}
