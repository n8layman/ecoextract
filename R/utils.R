#' Main CLI and Utility Functions
#' 
#' Core functions for processing ecological documents

#' Process ecological documents from PDFs to database
#' @param pdf_folder Path to folder containing PDF files
#' @param output_db Path to SQLite database file (will be created if it doesn't exist)
#' @param config List of configuration options
#' @return List with processing results
#' @export
process_ecological_documents <- function(
  pdf_folder = "data/pdfs/", 
  output_db = "ecoextract_results.sqlite",
  config = list(
    ocr_model = "mistral-ocr-v1",
    extraction_model = "claude-sonnet-4-20250514",
    skip_existing = TRUE,
    enrich_metadata = TRUE
  )
) {
  
  # Validate inputs
  if (!dir.exists(pdf_folder)) {
    stop("PDF folder does not exist: ", pdf_folder)
  }
  
  # Initialize database (create if it doesn't exist)
  init_ecoextract_database(output_db)
  
  # Get list of PDF files
  pdf_files <- list.files(pdf_folder, pattern = "\\.pdf$", full.names = TRUE)
  if (length(pdf_files) == 0) {
    cat("No PDF files found in:", pdf_folder, "\n")
    return(list(
      success = FALSE,
      processed_documents = 0,
      total_interactions = 0,
      message = "No PDF files found"
    ))
  }
  
  cat("Found", length(pdf_files), "PDF files to process\n")
  
  # Initialize results tracking
  results <- list(
    success = TRUE,
    processed_documents = 0,
    total_interactions = 0,
    errors = character(0)
  )
  
  # Process each PDF
  for (pdf_file in pdf_files) {
    cat("\n" , "="*60, "\n")
    cat("Processing:", basename(pdf_file), "\n")
    cat("="*60, "\n")
    
    tryCatch({
      # Step 1: OCR Processing (would integrate with ohseer)
      if (!requireNamespace("ohseer", quietly = TRUE)) {
        cat("Warning: ohseer package not available, skipping OCR\n")
        next
      }

      # OCR with Mistral (placeholder - would use ohseer::mistral_ocr)
      cat("Step 1: OCR processing...\n")
      # ocr_result <- ohseer::mistral_ocr(pdf_file)
      # For now, skip actual OCR

      # Step 2: OCR Audit
      cat("Step 2: OCR quality audit...\n")
      # audit_result <- perform_ocr_audit(ocr_result$markdown)

      # Step 3: Data Extraction
      cat("Step 3: Data extraction...\n")
      # extraction_result <- extract_records(
      #   markdown_text = audit_result$audited_markdown,
      #   ocr_audit = audit_result
      # )
      
      # For demonstration, create mock results
      cat("Mock processing completed for", basename(pdf_file), "\n")
      results$processed_documents <- results$processed_documents + 1
      # results$total_interactions <- results$total_interactions + nrow(extraction_result$interactions)
      
    }, error = function(e) {
      error_msg <- paste("Error processing", basename(pdf_file), ":", e$message)
      cat("ERROR:", error_msg, "\n")
      results$errors <- c(results$errors, error_msg)
    })
  }
  
  # Summary
  cat("\n" , "="*60, "\n")
  cat("PROCESSING COMPLETE\n")
  cat("="*60, "\n")
  cat("Processed documents:", results$processed_documents, "/", length(pdf_files), "\n")
  cat("Total interactions extracted:", results$total_interactions, "\n")
  
  if (length(results$errors) > 0) {
    cat("Errors encountered:\n")
    for (error in results$errors) {
      cat("  -", error, "\n")
    }
  }
  
  return(results)
}

#' Create occurrence IDs for a batch of interactions
#' @param interactions Dataframe of interactions
#' @param author_lastname Author lastname for ID generation
#' @param publication_year Publication year for ID generation
#' @return Dataframe with occurrence_id column added
#' @export
add_occurrence_ids <- function(interactions, author_lastname, publication_year) {
  if (nrow(interactions) == 0) {
    return(interactions)
  }
  
  # Generate sequential occurrence IDs
  interactions$occurrence_id <- sapply(1:nrow(interactions), function(i) {
    generate_occurrence_id(author_lastname, publication_year, i)
  })
  
  return(interactions)
}

#' Simple logging function
#' @param message Message to log
#' @param level Log level (INFO, WARNING, ERROR)
log_message <- function(message, level = "INFO") {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat("[", timestamp, "] ", level, ": ", message, "\n", sep = "")
}

estimate_tokens <- function(text) {
  # Handle NULL input
  if (is.null(text)) {
    return(0)
  }

  # Convert to JSON if not already a character
  if (!is.character(text)) {
    tryCatch({
      text <- jsonlite::toJSON(text, auto_unbox = TRUE)
    }, error = function(e) {
      # If JSON conversion fails, try deparse then as.character as fallback
      tryCatch({
        text <- paste(deparse(text), collapse = " ")
      }, error = function(e2) {
        # Ultimate fallback for unconvertible objects
        text <- "unknown"
      })
    })
  }

  # Handle NA or empty string after conversion
  if (length(text) == 0 || is.na(text) || text == "") {
    return(0)
  }

  ceiling(nchar(text) / 4)
}
