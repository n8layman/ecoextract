#' Ecological Data Refinement Functions
#' 
#' Refine and enhance extracted ecological interaction data

#' Refine extracted interactions with additional context
#' @param interactions Dataframe of extracted interactions to refine
#' @param markdown_text Original OCR-processed markdown content
#' @param ocr_audit Optional OCR quality analysis
#' @param document_id Optional document ID for context
#' @param refinement_prompt_file Path to custom refinement prompt file (optional)
#' @param refinement_context_file Path to custom refinement context template file (optional)
#' @param schema_file Path to custom schema JSON file (optional)
#' @param anthropic_key Optional Anthropic API key (uses environment variable if not provided)
#' @return List with refinement results
#' @export
refine_records <- function(interactions, markdown_text, ocr_audit = NULL, document_id = NULL,
                                refinement_prompt_file = NULL, refinement_context_file = NULL, schema_file = NULL,
                                anthropic_key = NULL) {
  if (is.null(interactions) || nrow(interactions) == 0) {
    cat("No existing interactions found for refinement\n")
    return(list(
      success = FALSE,
      interactions = data.frame(),
      prompt_hash = NULL,
      model = "claude-sonnet-4-20250514"
    ))
  }

  # Check API key availability
  api_key <- anthropic_key %||% get_anthropic_key()
  if (is.null(api_key)) {
    stop("Anthropic API key not found. Please set ANTHROPIC_API_KEY environment variable or run setup_env_file()")
  }

  # Load refinement schema (custom or default)
  schema <- load_schema(schema_file, schema_type = "refinement")

  # Load refinement prompt and context template (custom or default)
  refinement_prompt <- get_refinement_prompt(refinement_prompt_file)
  refinement_context_template <- get_extraction_context_template(refinement_context_file)

  # Calculate prompt hash for model tracking
  prompt_hash <- digest::digest(paste(refinement_prompt, refinement_context_template, sep = "\n"), algo = "md5")

  # Build context for refinement
  existing_context <- build_existing_records_context(interactions, document_id)

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
  cat("Calling claude-sonnet-4-20250514 for refinement\n")
  refine_chat <- ellmer::chat_anthropic(
    system_prompt = refinement_prompt,
    model = "claude-sonnet-4-20250514",
    echo = "none",
    params = list(max_tokens = 8192)
  )

  # Build refinement context
  refinement_context <- glue::glue(refinement_context_template,
    document_content = markdown_text,
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
  if (is.list(refine_result) && "interactions" %in% names(refine_result)) {
    # Convert interactions list to dataframe
    interactions_list <- refine_result$interactions
    if (length(interactions_list) > 0) {
      refined_df <- jsonlite::fromJSON(jsonlite::toJSON(interactions_list), simplifyVector = TRUE)
    } else {
      refined_df <- data.frame()
    }
  } else {
    # Might be the interactions dataframe directly
    refined_df <- refine_result
  }
  
  # Process dataframe if valid
  if (is.data.frame(refined_df) && nrow(refined_df) > 0) {
    cat("\nRefinement output:\n")
    print(refined_df)
    cat("Rows refined:", nrow(refined_df), "interactions\n")
    
    return(list(
      success = TRUE,
      interactions = refined_df,
      prompt_hash = prompt_hash,
      model = "claude-sonnet-4-20250514"
    ))
  } else {
    cat("No valid refined interactions returned\n")
    return(list(
      success = FALSE,
      interactions = data.frame(),
      prompt_hash = prompt_hash,
      model = "claude-sonnet-4-20250514"
    ))
  }
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
    
    # Format organism information
    bat_info <- paste0(row$bat_species_scientific_name, " (", row$bat_species_common_name, ")")
    
    org_sci <- if (is.na(row$interacting_organism_scientific_name) || row$interacting_organism_scientific_name == "") {
      "[MISSING: scientific name]"
    } else {
      row$interacting_organism_scientific_name
    }
    
    org_common <- if (is.na(row$interacting_organism_common_name) || row$interacting_organism_common_name == "") {
      "[MISSING: common name]"
    } else {
      row$interacting_organism_common_name
    }
    
    org_desc <- if (org_sci == "[MISSING: scientific name]" && org_common == "[MISSING: common name]") {
      "[MISSING: organism details]"
    } else if (org_sci == "[MISSING: scientific name]") {
      paste0(org_common, " [incomplete: missing scientific name]")
    } else if (org_common == "[MISSING: common name]") {
      paste0(org_sci, " [incomplete: missing common name]")
    } else {
      paste0(org_sci, " (", org_common, ")")
    }
    
    # Format location
    location_desc <- if (is.na(row$location) || row$location == "") {
      ""
    } else {
      paste0(" at ", row$location)
    }
    
    # Build context line
    occurrence_id <- if ("occurrence_id" %in% names(row) && !is.na(row$occurrence_id)) {
      row$occurrence_id
    } else {
      paste0("interaction-", i)
    }
    
    context_line <- paste0("- ", occurrence_id, ": ", bat_info, " <-> ", org_desc, location_desc)
    context_lines <- c(context_lines, context_line)
  }
  
  return(paste(context_lines, collapse = "\n"))
}