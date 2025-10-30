#' Complete Document Processing Workflow
#'
#' Process PDFs through the complete pipeline: OCR → Audit → Extract → Refine
#'
#' @param pdf_path Path to a single PDF file or directory of PDFs
#' @param db_path Path to SQLite database (default: "ecoextract_records.db" in current directory, will be created if doesn't exist)
#' @param schema_file Optional custom schema file
#' @param extraction_prompt_file Optional custom extraction prompt
#' @param refinement_prompt_file Optional custom refinement prompt
#' @param skip_existing Skip files already processed in database
#' @return List with processing results
#' @export
#'
#' @examples
#' \dontrun{
#' # Process all PDFs in a folder (uses default database)
#' process_documents("pdfs/")
#'
#' # Process a single PDF with custom database
#' process_documents("paper.pdf", "my_interactions.db")
#'
#' # With custom schema and prompts
#' process_documents("pdfs/", "interactions.db",
#'                   schema_file = "ecoextract/schema.json",
#'                   extraction_prompt_file = "ecoextract/extraction_prompt.md")
#' }
process_documents <- function(pdf_path,
                             db_path = "ecoextract_records.db",
                             schema_file = NULL,
                             extraction_prompt_file = NULL,
                             refinement_prompt_file = NULL,
                             skip_existing = TRUE) {

  # Determine if processing single file or directory
  if (file.exists(pdf_path)) {
    if (dir.exists(pdf_path)) {
      # Process directory
      pdf_files <- list.files(pdf_path, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
      if (length(pdf_files) == 0) {
        stop("No PDF files found in directory: ", pdf_path)
      }
      cat("Found", length(pdf_files), "PDF files to process\n\n")
    } else if (grepl("\\.pdf$", pdf_path, ignore.case = TRUE)) {
      # Single file
      pdf_files <- pdf_path
    } else {
      stop("Path must be a PDF file or directory: ", pdf_path)
    }
  } else {
    stop("Path does not exist: ", pdf_path)
  }

  # Initialize database
  if (!file.exists(db_path)) {
    cat("Initializing new database:", db_path, "\n")
    init_ecoextract_database(db_path)
  }
  db_conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(db_conn), add = TRUE)

  # Track timing
  start_time <- Sys.time()

  # Process each PDF and collect results
  results_list <- list()

  for (pdf_file in pdf_files) {
    result <- process_single_document(
      pdf_file = pdf_file,
      db_conn = db_conn,
      schema_file = schema_file,
      extraction_prompt_file = extraction_prompt_file,
      refinement_prompt_file = refinement_prompt_file,
      skip_existing = skip_existing
    )
    results_list[[length(results_list) + 1]] <- result
  }

  end_time <- Sys.time()

  # Convert results to tibble
  results_tibble <- tibble::tibble(
    filename = sapply(results_list, function(x) x$filename),
    document_id = sapply(results_list, function(x) x$document_id %||% NA),
    ocr_status = sapply(results_list, function(x) x$ocr_status),
    audit_status = sapply(results_list, function(x) x$audit_status %||% NA),
    extraction_status = sapply(results_list, function(x) x$extraction_status),
    refinement_status = sapply(results_list, function(x) x$refinement_status),
    records_extracted = sapply(results_list, function(x) x$records_extracted %||% 0)
  )

  # Calculate summary stats
  total_rows <- sum(results_tibble$records_extracted, na.rm = TRUE)
  skipped <- sum(results_tibble$ocr_status == "skipped")
  errors <- sum(
    !results_tibble$ocr_status %in% c("completed", "skipped") |
    !results_tibble$extraction_status %in% c("completed", "skipped") |
    !results_tibble$refinement_status %in% c("completed", "skipped")
  )
  processed <- nrow(results_tibble) - skipped - errors

  # Add attributes
  attr(results_tibble, "start_time") <- start_time
  attr(results_tibble, "end_time") <- end_time
  attr(results_tibble, "duration") <- as.numeric(difftime(end_time, start_time, units = "secs"))
  attr(results_tibble, "total_rows") <- total_rows
  attr(results_tibble, "database") <- db_path

  # Summary
  cat("\n", strrep("=", 70), "\n")
  cat("PROCESSING COMPLETE\n")
  cat(strrep("=", 70), "\n")
  cat("Total files:", nrow(results_tibble), "\n")
  cat("Processed:", processed, "\n")
  cat("Skipped:", skipped, "\n")
  cat("Errors:", errors, "\n")
  cat("Total rows extracted:", total_rows, "\n")
  cat("Duration:", round(attr(results_tibble, "duration"), 2), "seconds\n")
  cat("Database:", db_path, "\n")
  cat(strrep("=", 70), "\n\n")

  results_tibble
}

#' Process Single Document Through Complete Pipeline
#'
#' @param pdf_file Path to PDF file
#' @param db_conn Database connection
#' @param schema_file Optional custom schema
#' @param extraction_prompt_file Optional custom extraction prompt
#' @param refinement_prompt_file Optional custom refinement prompt
#' @param skip_existing Skip if already in database
#' @return List with processing result
#' @keywords internal
process_single_document <- function(pdf_file,
                                    db_conn,
                                    schema_file = NULL,
                                    extraction_prompt_file = NULL,
                                    refinement_prompt_file = NULL,
                                    skip_existing = TRUE) {

  # Log header
  message(strrep("=", 70))
  message(glue::glue("Processing: {basename(pdf_file)}"))
  message(strrep("=", 70))

  # Initialize status tracking with filename only
  status_tracking <- list(filename = basename(pdf_file),
                          ocr_status = "skipped",
                          audit_status = "skipped",
                          extraction_status = "skipped",
                          records_extracted = 0,
                          refinement_status = "skipped")

  # Step 1: OCR Processing
  message("\n[1/4] OCR Processing...")
  ocr_result <- ocr_document(pdf_file, db_conn, skip_existing)
  status_tracking$document_id <- ocr_result$document_id
  status_tracking$ocr_status <- ocr_result$status
  if(status_tracking$ocr_status != "completed") {
    message(paste("OCR error detected:", status_tracking$ocr_status))
    return(status_tracking)
  }

  # Step 2: OCR Audit
  message("\n[2/4] OCR Quality Audit...")
  audit_result <- audit_ocr(status_tracking$document_id, db_conn)
  status_tracking$audit_status <- audit_result$status
  if(status_tracking$audit_status != "completed") {
    message(paste("audit OCR error detected:", status_tracking$audit_status))
    return(status_tracking)
  }

  # Step 3: Extract interactions
  message("\n[3/4] Extracting Interactions...")
  extraction_result <- extract_records(
    document_id = status_tracking$document_id,
    interaction_db = db_conn,
    schema_file = schema_file,
    extraction_prompt_file = extraction_prompt_file
  )
  status_tracking$extraction_status <- extraction_result$status
  status_tracking$records_extracted <- extraction_result$records_extracted %||% 0
  if(status_tracking$extraction_status != "completed") {
    message(paste("Extraction error detected:", status_tracking$extraction_status))
    return(status_tracking)
  }

  # Step 4: Refine interactions
  # Note: records_extracted should be measured after refinement. Sometimes extraction will skip (if records already exist. Refinement never will.)
  message("\n[4/4] Refining Interactions...")
  refinement_result <- refine_records(
    db_conn = db_conn,
    document_id = status_tracking$document_id,
    extraction_prompt_file = extraction_prompt_file,
    schema_file = schema_file,
    refinement_prompt_file = refinement_prompt_file
  )
  status_tracking$refinement_status <- refinement_result$status
  if(status_tracking$refinement_status != "completed") {
    message(paste("Refinement error detected:", status_tracking$refinement_status))
    return(status_tracking)
  }

  # Summary
  message(strrep("-", 70))
  message(glue::glue("SUCCESS: {status_tracking$records_extracted} records in database"))
  message(strrep("-", 70))

  return(status_tracking)
}
