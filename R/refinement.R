#' Ecological Data Refinement Functions
#' 
#' Refine and enhance extracted ecological interaction data

#' Refine extracted interactions with additional context
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

    if (nrow) {
      message("No existing records found - refinement will attempt fresh extraction")
    }

    # Filter out human-edited and rejected records
    # We need to be careful here. We filter these out the LLM may just find them again but sligthly different
    # CLAUDE: how should we deal with this simply? Tell me the plan do not automatically execute the fix without approval.
    if (nrow(existing_records) > 0) {
      protected_count <- sum(interactions$human_edited | interactions$rejected, na.rm = TRUE)
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
    existing_context <- build_existing_records_context(interactions, document_id)

    # CLAUDE: We shouldn't need to test this. OCR audit must be available to reach this stage.
    audit_context <- if (is.null(ocr_audit)) {
      "No OCR audit available. No specific human edit audit context available."
    } else {
      paste("OCR Quality Analysis:", ocr_audit, "Human Edit Audit: No specific human edit audit context available.")
    }

    # Report inputs
    markdown_chars <- nchar(markdown_text)
    interaction_count <- nrow(interactions)
    cat("Inputs loaded: OCR data (", markdown_chars, " chars), OCR audit (", nchar(ocr_audit %||% ""), " chars), ", interaction_count, " interactions, refinement prompt (", nchar(refinement_prompt), " chars, hash:", substring(prompt_hash, 1, 8), ")\n")

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
      existing_interactions_context = existing_context,
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

    # Now extract the interactions
    # CLAUDE: We need to change this to be generic and not dependant on the specific schema. We're standardizing on 'records' though some schemas may have an interactions table.
    if (is.list(refine_result) && "interactions" %in% names(refine_result)) {
      # Convert interactions list to tibble
      interactions_list <- refine_result$interactions
      if (length(interactions_list) > 0) {
        refined_df <- tibble::as_tibble(jsonlite::fromJSON(jsonlite::toJSON(interactions_list), simplifyVector = TRUE))
      } else {
        refined_df <- tibble::tibble()
      }
    } else {
      # Might be the interactions dataframe directly
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
        records_extracted = nrow(refined_df)
      ))
    } else {
      message("No valid refined records returned")
      return(list(
        status = "completed",
        records_extracted = 0
      ))
    }
  }, error = function(e) {
    return(list(
      status = paste("Refinement failed:", e$message),
      records_extracted = 0
    ))
  })
}

#' Merge refined data back into original interactions
#' @param original_interactions Dataframe of original interactions
#' @param refined_interactions Dataframe of refined interactions
#' @return Dataframe with merged refinements
#' @export
merge_refinements <- function(original_interactions, refined_interactions) {
  if (nrow(refined_interactions) == 0) {
    return(original_interactions)
  }
  
  # Create a copy of original interactions to update
  updated_interactions <- original_interactions
  
  # Update each refined interaction
  for (i in 1:nrow(refined_interactions)) {
    refined_row <- refined_interactions[i, ]
    
    # Find matching original interaction by occurrence_id
    if ("occurrence_id" %in% names(refined_row) && "occurrence_id" %in% names(updated_interactions)) {
      match_idx <- which(updated_interactions$occurrence_id == refined_row$occurrence_id)
      
      if (length(match_idx) > 0) {
        # Update fields from refined data
        for (col_name in names(refined_row)) {
          if (col_name %in% names(updated_interactions)) {
            updated_interactions[match_idx[1], col_name] <- refined_row[[col_name]]
          }
        }
      }
    }
  }
  
  return(updated_interactions)
}

#' Build context string for existing interactions (same as extraction.R for consistency)
#' @param existing_interactions Dataframe of existing interactions
#' @param document_id Document ID for getting human edit summary
#' @return Character string with formatted context
build_existing_records_context <- function(existing_interactions, document_id = NULL) {
  if (is.null(existing_interactions) || !is.data.frame(existing_interactions) || nrow(existing_interactions) == 0) {
    return("No interactions have been extracted from this document yet.")
  }
  
  # Simple context building without database dependencies
  context_lines <- c("Existing interactions:", "")
  
  for (i in 1:nrow(existing_interactions)) {
    row <- existing_interactions[i, ]

    # Helper function to safely extract scalar value from potentially list column or missing column
    safe_extract <- function(col_name) {
      if (!col_name %in% names(row)) return(NA_character_)
      x <- row[[col_name]]
      if (is.list(x)) x <- unlist(x)
      if (length(x) == 0) return(NA_character_)
      x <- as.character(x)
      if (is.na(x) || x == "") NA_character_ else x
    }

    # Format organism information
    bat_sci <- safe_extract("bat_species_scientific_name")
    bat_common <- safe_extract("bat_species_common_name")
    bat_info <- paste0(
      if (is.na(bat_sci)) "[MISSING]" else bat_sci,
      " (",
      if (is.na(bat_common)) "[MISSING]" else bat_common,
      ")"
    )

    org_sci <- safe_extract("interacting_organism_scientific_name")
    org_common <- safe_extract("interacting_organism_common_name")

    org_desc <- if (is.na(org_sci) && is.na(org_common)) {
      "[MISSING: organism details]"
    } else if (is.na(org_sci)) {
      paste0(org_common, " [incomplete: missing scientific name]")
    } else if (is.na(org_common)) {
      paste0(org_sci, " [incomplete: missing common name]")
    } else {
      paste0(org_sci, " (", org_common, ")")
    }

    # Format location
    location_val <- safe_extract("location")
    location_desc <- if (is.na(location_val)) "" else paste0(" at ", location_val)

    # Build context line
    occurrence_id_val <- safe_extract("occurrence_id")
    occurrence_id <- if (!is.na(occurrence_id_val)) occurrence_id_val else paste0("interaction-", i)

    context_line <- paste0("- ", occurrence_id, ": ", bat_info, " <-> ", org_desc, location_desc)
    context_lines <- c(context_lines, context_line)
  }
  
  return(paste(context_lines, collapse = "\n"))
}
