#' Ecological Data Extraction Functions
#' 
#' Extract structured ecological interaction data from OCR-processed documents

#' Extract interactions from markdown text
#' @param markdown_text OCR-processed markdown content
#' @param ocr_audit Optional OCR quality analysis
#' @param existing_interactions Optional dataframe of existing interactions
#' @param document_id Optional document ID for context
#' @return List with extraction results
#' @export
# CLAUDE I LEFT OF WORKING ON THIS HERE. WE'RE GOIN TO NEED TO REFACTOR REFINEMENT IN A SIMILAR WAY.
extract_interactions <- function(document_id = NA,
                                 interaction_db = NA,
                                 document_content = NA,
                                 ocr_audit = NA,
                                 existing_interactions = NA, # Needs to be JSON or character representation of JSON
                                 extraction_prompt_file = "data/extraction_prompt.md",
                                 extraction_context_file = "data/extraction_context.md",
                                 schema_file = system.file("extdata", "interaction_schema.R", package = "ecoextract"),
                                 model = "claude-sonnet-4-20250514",
                                 anthropic_key = NULL,
                                 ...) {

  # Check API key availability  
  api_key <- anthropic_key %||% get_anthropic_key()
  if (is.null(api_key)) {
    stop("Anthropic API key not found. Please set ANTHROPIC_API_KEY environment variable or run setup_env_file()")
  }

  # Document content must be available either through the db or provided
  # otherwise gracefully exit and suggest OCR
  if(!is.na(document_id)) {
    document_content <- get_document_content(document_id)
    ocr_audit = get_ocr_audit(document_id)
    existing_interactions = get_existing_interactions(document_id)
  }
  if(is.na(document_content)) {
    stop("ERROR message please provide either the id of a document in the database or markdown OCR document content.")
  }    

  # Schema must be made available and be valid ellmer schema otherwise exit with message.
  # This will be an object like type_extraction_result object. See data/interaction_schema.R
  if (!file.exists(schema_file)) {
    stop("Schema file not found: ", schema_file)
  }
  source(schema_file)
  if (!exists("type_extraction_result")) {
    stop("Schema file must define 'type_extraction_result' object")
  }
  schema <- type_extraction_result

  # Read in and process extraction context
  extraction_context_template <- paste(readLines(extraction_context_file), collapse = "\n")
  extraction_context <- glue::glue(extraction_context_template, .na = "", .null = "") # Don't forget the .null!

  # Read in and process extraction prompt
  extraction_prompt <- paste(readLines(extraction_prompt_file), collapse = "\n")
  extraction_prompt_hash <- digest::digest(extraction_prompt, algo = "md5")  

  # Process existing interactions.
  existing_interactions <- as.character(existing_interactions)

  # Caluclate the nchar size of every variable in extraction_content_values 
  # Caluclate the nchar size of prompt
  # Log those values to console as in:
  cat(glue::glue(
    "Inputs loaded: Document content ({estimate_tokens(document_content)} tokens), OCR audit ({estimate_tokens(ocr_audit)} chars), {nrow(existing_interactions)} existing interactions, extraction prompt (hash:{substring(extraction_prompt_hash, 1, 8)}, {estimate_tokens(extraction_prompt)} tokens)",
    .na = "0",
    .null = "0"
  ), "\n")
    
  # Initialize extraction chat
  cat("Calling claude-sonnet-4-20250514 for extraction\n")
  extract_chat <- ellmer::chat_anthropic(
    system_prompt = extraction_prompt, 
    model = model, 
    echo = "none", 
    params = list(max_tokens = 8192)
  )
  
  # Execute extraction
  extract_result <- extract_chat$chat(extraction_context, schema = schema)
  
  # Process result
  cat("Raw extraction response length:", nchar(extract_result$content), "characters\n")
  
  # Get JSON preview
  json_preview <- substr(extract_result$structured_output, 1, 200)
  cat("JSON text preview:", json_preview, "...\n")
  
  # Convert to dataframe
  extraction_df <- extract_result$structured_output$interactions
  
  # Extract publication metadata if available
  pub_metadata <- extract_result$structured_output$publication_metadata
  
  # Process dataframe if valid
  if (is.data.frame(extraction_df) && nrow(extraction_df) > 0) {
    cat("\nExtraction output:\n")
    print(extraction_df)
    cat("Rows extracted:", nrow(extraction_df), "interactions\n")
    
    return(list(
      success = TRUE,
      interactions = extraction_df,
      publication_metadata = pub_metadata,
      prompt_hash = extraction_prompt_hash,
      model = "claude-sonnet-4-20250514"
    ))
  } else {
    cat("No valid interactions extracted\n")
    return(list(
      success = FALSE,
      interactions = data.frame(),
      publication_metadata = pub_metadata,
      prompt_hash = extraction_prompt_hash,
      model = "claude-sonnet-4-20250514"
    ))
  }
}

#' Generate occurrence ID for interaction
#' @param author_lastname Author surname
#' @param publication_year Publication year
#' @param sequence_number Sequence number for this interaction
#' @return Character occurrence ID
#' @export
generate_occurrence_id <- function(author_lastname, publication_year, sequence_number = 1) {
  # Clean author name
  clean_author <- stringr::str_replace_all(author_lastname, "[^A-Za-z]", "")
  if (nchar(clean_author) == 0) clean_author <- "Author"
  
  # Create occurrence ID
  paste0(clean_author, publication_year, "-o", sequence_number)
}

#' Build context string for existing interactions
#' @param existing_interactions Dataframe of existing interactions
#' @param document_id Document ID for getting human edit summary
#' @return Character string with formatted context
build_existing_interactions_context <- function(existing_interactions, document_id = NULL) {
  if (is.null(existing_interactions) || nrow(existing_interactions) == 0) {
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
    
    context_line <- paste0("- ", occurrence_id, ": ", bat_info, " ↔ ", org_desc, location_desc)
    context_lines <- c(context_lines, context_line)
  }
  
  return(paste(context_lines, collapse = "\n"))
}
