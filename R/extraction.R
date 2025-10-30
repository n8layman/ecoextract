#' Ecological Data Extraction Functions
#' 
#' Extract structured ecological interaction data from OCR-processed documents

#' Extract records from markdown text
#' @param document_id Optional document ID for context
#' @param interaction_db Optional path to interaction database
#' @param document_content OCR-processed markdown content
#' @param ocr_audit Optional OCR quality analysis
#' @param extraction_prompt_file Path to custom extraction prompt file (optional)
#' @param extraction_context_file Path to custom extraction context template file (optional)
#' @param schema_file Path to custom schema JSON file (optional)
#' @param model Provider and model in format "provider/model" (default: "anthropic/claude-sonnet-4-20250514")
#' @param ... Additional arguments passed to extraction
#' @return List with extraction results
#' @export
extract_records <- function(document_id = NA,
                                 interaction_db = NA,
                                 document_content = NA,
                                 ocr_audit = NA,
                                 extraction_prompt_file = NULL,
                                 extraction_context_file = NULL,
                                 schema_file = NULL,
                                 model = "anthropic/claude-sonnet-4-20250514",
                                 ...) {

  # Document content must be available either through the db or provided
  # otherwise gracefully exit and suggest OCR
  # CLAUDE: I removed existing records from context. Initial extraction should only run when db is empty. Otherwise we should just refine what is there since refinment can also find new records UPSERT
  if(!is.na(document_id) && !inherits(interaction_db, "logical")) {
    document_content <- get_document_content(document_id, interaction_db)
    ocr_audit = get_ocr_audit(document_id, interaction_db)
    existing_records = get_existing_records(document_id, interaction_db)
    if(nrow(existing_records) > 0) {
      return(list(
          status = "skipped",
          records_extracted = NA
        ))
    }
  }
  if(is.na(document_content)) {
    stop("ERROR message please provide either the id of a document in the database or markdown OCR document content.")
  }

  tryCatch({
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

    # Load extraction prompt (custom or default)
    extraction_prompt <- get_extraction_prompt(extraction_prompt_file)
    extraction_prompt_hash <- digest::digest(extraction_prompt, algo = "md5")

    # Load extraction context template (custom or default)
    extraction_context_template <- get_extraction_context_template(extraction_context_file)
    extraction_context <- glue::glue(extraction_context_template, .na = "", .null = "")

    # Calculate the nchar size of every variable in extraction_content_values
    # Calculate the nchar size of prompt
    # Log those values to console as in:
    cat(glue::glue(
      "Inputs loaded: Document content ({estimate_tokens(document_content)} tokens), OCR audit ({estimate_tokens(ocr_audit)} chars), extraction prompt (hash:{substring(extraction_prompt_hash, 1, 8)}, {estimate_tokens(extraction_prompt)} tokens)",
      .na = "0",
      .null = "0"
    ), "\n")

    # Initialize extraction chat
    cat("Calling", model, "for extraction\n")
    extract_chat <- ellmer::chat(
      name = model,
      system_prompt = extraction_prompt,
      echo = "none",
      params = list(max_tokens = 8192)
    )

    # Execute extraction with structured output
    extract_result <- extract_chat$chat_structured(extraction_context, type = schema)

    # Process result - chat_structured can return either a list or JSON string
    cat("Extraction completed\n")

    # Parse if it's a JSON string
    if (is.character(extract_result)) {
      extract_result <- jsonlite::fromJSON(extract_result, simplifyVector = FALSE)
    }

    # Now extract the records
    # ellmer automatically converts array of objects to data.frame
    if (is.list(extract_result) && "records" %in% names(extract_result)) {
      records_data <- extract_result$records
      if (is.data.frame(records_data) && nrow(records_data) > 0) {
        extraction_df <- tibble::as_tibble(records_data)
      } else {
        extraction_df <- tibble::tibble()
      }
      pub_metadata <- extract_result$publication_metadata
    } else {
      # Might be the records dataframe directly
      extraction_df <- tibble::as_tibble(extract_result)
      pub_metadata <- NULL
    }

    # Process dataframe if valid
    if (is.data.frame(extraction_df) && nrow(extraction_df) > 0) {
      message("\nExtraction output:")
      print(extraction_df)
      message(glue::glue("Extracted {nrow(extraction_df)} records"))

      # Save to database (atomic step)
      if (!is.na(document_id) && !inherits(interaction_db, "logical")) {
        save_records_to_db(
          db_path = interaction_db@dbname,
          document_id = document_id,
          interactions_df = extraction_df,
          metadata = list(
            model = model,
            prompt_hash = extraction_prompt_hash
          )
        )

        return(list(
          status = "completed",
          records_extracted = nrow(extraction_df)
        ))
      } else {
        # No DB connection - return data without saving
        return(list(
          status = "completed (not saved - no DB connection)",
          records_extracted = nrow(extraction_df),
          records = extraction_df  # Include data when not saving
        ))
      }
    } else {
      message("No valid records extracted")
      return(list(
        status = "completed",
        records_extracted = 0
      ))
    }
  }, error = function(e) {
    return(list(
      status = paste("Extraction failed:", e$message),
      records_extracted = 0
    ))
  })
}

# CLAUDE: THis is generic enough. All papers will have author and pub year. And the point of this package is to extract data from pubs. Schemas might be differnt but this will be the same
#' Generate occurrence ID for interaction (internal)
#' @param author_lastname Author surname
#' @param publication_year Publication year
#' @param sequence_number Sequence number for this interaction
#' @return Character occurrence ID
#' @keywords internal
generate_occurrence_id <- function(author_lastname, publication_year, sequence_number = 1) {
  # Clean author name
  clean_author <- stringr::str_replace_all(author_lastname, "[^A-Za-z]", "")
  if (nchar(clean_author) == 0) clean_author <- "Author"
  
  # Create occurrence ID
  paste0(clean_author, publication_year, "-o", sequence_number)
}
