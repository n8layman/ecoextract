#' Ecological Data Extraction Functions
#' 
#' Extract structured ecological interaction data from OCR-processed documents

#' Extract interactions from markdown text
#' @param document_id Optional document ID for context
#' @param interaction_db Optional path to interaction database
#' @param document_content OCR-processed markdown content
#' @param ocr_audit Optional OCR quality analysis
#' @param existing_interactions Optional dataframe of existing interactions (JSON or character)
#' @param extraction_prompt_file Path to custom extraction prompt file (optional)
#' @param extraction_context_file Path to custom extraction context template file (optional)
#' @param schema_file Path to custom schema JSON file (optional)
#' @param model Provider and model in format "provider/model" (default: "anthropic/claude-sonnet-4-20250514")
#' @param api_key Optional API key for the provider (uses environment variable if not provided)
#' @param ... Additional arguments passed to extraction
#' @return List with extraction results
#' @export
extract_records <- function(document_id = NA,
                                 interaction_db = NA,
                                 document_content = NA,
                                 ocr_audit = NA,
                                 existing_interactions = NA,
                                 extraction_prompt_file = NULL,
                                 extraction_context_file = NULL,
                                 schema_file = NULL,
                                 model = "anthropic/claude-sonnet-4-20250514",
                                 api_key = NULL,
                                 ...) {

  # Detect provider from model string
  provider <- strsplit(model, "/")[[1]][1]

  # Check API key availability based on provider
  if (is.null(api_key)) {
    api_key <- if (provider == "anthropic") {
      get_anthropic_key()
    } else {
      Sys.getenv(paste0(toupper(provider), "_API_KEY"))
    }
  }

  if (is.null(api_key) || api_key == "") {
    stop("API key not found for provider '", provider, "'. Please set ",
         toupper(provider), "_API_KEY environment variable.")
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

  # Load extraction schema (custom or default)
  schema <- load_schema(schema_file, schema_type = "extraction")

  # Load extraction prompt (custom or default)
  extraction_prompt <- get_extraction_prompt(extraction_prompt_file)
  extraction_prompt_hash <- digest::digest(extraction_prompt, algo = "md5")

  # Build existing interactions context
  existing_interactions_context <- build_existing_records_context(existing_interactions)

  # Load extraction context template (custom or default)
  extraction_context_template <- get_extraction_context_template(extraction_context_file)
  extraction_context <- glue::glue(extraction_context_template, .na = "", .null = "")

  # Calculate the nchar size of every variable in extraction_content_values
  # Calculate the nchar size of prompt
  # Log those values to console as in:
  num_existing <- if (is.data.frame(existing_interactions)) nrow(existing_interactions) else 0
  cat(glue::glue(
    "Inputs loaded: Document content ({estimate_tokens(document_content)} tokens), OCR audit ({estimate_tokens(ocr_audit)} chars), {num_existing} existing interactions, extraction prompt (hash:{substring(extraction_prompt_hash, 1, 8)}, {estimate_tokens(extraction_prompt)} tokens)",
    .na = "0",
    .null = "0"
  ), "\n")
    
  # Initialize extraction chat
  cat("Calling", model, "for extraction\n")
  extract_chat <- ellmer::chat(
    name = model,
    system_prompt = extraction_prompt,
    echo = "none",
    params = list(max_tokens = 8192),
    api_key = api_key
  )

  # Execute extraction with structured output
  extract_result <- extract_chat$chat_structured(extraction_context, type = schema)

  # Process result - chat_structured can return either a list or JSON string
  cat("Extraction completed\n")

  # Parse if it's a JSON string
  if (is.character(extract_result)) {
    extract_result <- jsonlite::fromJSON(extract_result, simplifyVector = FALSE)
  }

  # Now extract the interactions
  if (is.list(extract_result) && "interactions" %in% names(extract_result)) {
    # Convert interactions list to dataframe
    interactions_list <- extract_result$interactions
    if (length(interactions_list) > 0) {
      extraction_df <- jsonlite::fromJSON(jsonlite::toJSON(interactions_list), simplifyVector = TRUE)
    } else {
      extraction_df <- data.frame()
    }
    pub_metadata <- extract_result$publication_metadata
  } else {
    # Might be the interactions dataframe directly
    extraction_df <- extract_result
    pub_metadata <- NULL
  }
  
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
      model = model
    ))
  } else {
    cat("No valid interactions extracted\n")
    return(list(
      success = FALSE,
      interactions = data.frame(),
      publication_metadata = pub_metadata,
      prompt_hash = extraction_prompt_hash,
      model = model
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
