#' Complete Document Processing Workflow
#'
#' Process PDFs through the complete pipeline: OCR → Audit → Extract → Refine
#'
#' @param pdf_path Path to a single PDF file or directory of PDFs
#' @param db_conn Database connection (any DBI backend) or path to SQLite database file.
#'   If a path is provided, creates SQLite database if it doesn't exist.
#'   If a connection is provided, tables must already exist (use \code{init_ecoextract_database()} first).
#' @param schema_file Optional custom schema file
#' @param extraction_prompt_file Optional custom extraction prompt
#' @param refinement_prompt_file Optional custom refinement prompt
#' @param run_extraction If TRUE, run extraction step (default: TRUE)
#' @param run_refinement If TRUE, run refinement step (default: TRUE)
#' @param force_reprocess If TRUE, re-run all steps even if outputs exist (default: FALSE)
#' @return Tibble with processing results
#' @export
#'
#' @examples
#' \dontrun{
#' # SQLite (path string - automatic initialization)
#' process_documents("pdfs/")
#' process_documents("paper.pdf", "my_interactions.db")
#'
#' # Remote database (Supabase, PostgreSQL, etc.)
#' library(RPostgres)
#' con <- dbConnect(Postgres(),
#'   dbname = "your_db",
#'   host = "db.xxx.supabase.co",
#'   user = "postgres",
#'   password = Sys.getenv("SUPABASE_PASSWORD")
#' )
#' # Initialize schema first
#' init_ecoextract_database(con)
#' # Then process documents
#' process_documents("pdfs/", db_conn = con)
#' dbDisconnect(con)
#'
#' # Force reprocess existing documents
#' process_documents("pdfs/", force_reprocess = TRUE)
#'
#' # With custom schema and prompts
#' process_documents("pdfs/", "interactions.db",
#'                   schema_file = "ecoextract/schema.json",
#'                   extraction_prompt_file = "ecoextract/extraction_prompt.md")
#'
#' # Skip refinement (extraction only)
#' process_documents("pdfs/", run_refinement = FALSE)
#'
#' # Skip extraction (refinement only on existing records)
#' process_documents("pdfs/", run_extraction = FALSE)
#' }
process_documents <- function(pdf_path,
                             db_conn = "ecoextract_records.db",
                             schema_file = NULL,
                             extraction_prompt_file = NULL,
                             refinement_prompt_file = NULL,
                             run_extraction = TRUE,
                             run_refinement = TRUE,
                             force_reprocess = FALSE) {

  # Determine if processing single file, multiple files, or directory
  if (length(pdf_path) > 1) {
    # Multiple files provided as vector
    pdf_files <- pdf_path
    # Check all files exist
    missing <- pdf_files[!file.exists(pdf_files)]
    if (length(missing) > 0) {
      stop("Files do not exist: ", paste(missing, collapse = ", "))
    }
  } else if (file.exists(pdf_path)) {
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

  # Handle database connection - accept either connection object or path
  if (inherits(db_conn, "DBIConnection")) {
    # User provided connection - use it directly, don't close on exit
    con <- db_conn
    close_on_exit <- FALSE
  } else {
    # Path string - initialize if needed, then connect
    if (!file.exists(db_conn)) {
      cat("Initializing new database:", db_conn, "\n")
      init_ecoextract_database(db_conn, schema_file = schema_file)
    }
    con <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    close_on_exit <- TRUE
  }

  if (close_on_exit) {
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }

  # Report configuration sources
  schema_src <- detect_config_source(schema_file, "schema.json", "extdata")
  extraction_src <- detect_config_source(extraction_prompt_file, "extraction_prompt.md", "prompts")

  if (schema_src$source == "package" && extraction_src$source == "package") {
    cat("Using package default schema and extraction prompt\n")
    cat("  Run init_ecoextract() to customize for your domain\n\n")
  } else {
    cat("Configuration:\n")
    if (schema_src$source != "package") {
      cat("  Schema:", schema_src$source, "-", schema_src$path, "\n")
    }
    if (extraction_src$source != "package") {
      cat("  Extraction prompt:", extraction_src$source, "-", extraction_src$path, "\n")
    }
    cat("\n")
  }

  # Track timing
  start_time <- Sys.time()

  # Process each PDF and collect results
  results_list <- list()

  for (pdf_file in pdf_files) {
    result <- process_single_document(
      pdf_file = pdf_file,
      db_conn = con,
      schema_file = schema_file,
      extraction_prompt_file = extraction_prompt_file,
      refinement_prompt_file = refinement_prompt_file,
      run_extraction = run_extraction,
      run_refinement = run_refinement,
      force_reprocess = force_reprocess
    )
    results_list[[length(results_list) + 1]] <- result
  }

  end_time <- Sys.time()

  # Convert results to tibble
  results_tibble <- tibble::tibble(
    filename = sapply(results_list, function(x) x$filename),
    document_id = sapply(results_list, function(x) x$document_id %||% NA),
    ocr_status = sapply(results_list, function(x) x$ocr_status),
    metadata_status = sapply(results_list, function(x) x$metadata_status),
    extraction_status = sapply(results_list, function(x) x$extraction_status),
    refinement_status = sapply(results_list, function(x) x$refinement_status),
    records_extracted = sapply(results_list, function(x) x$records_extracted %||% 0)
  )

  # Calculate summary stats using matrix approach (like tests)
  total_rows <- sum(results_tibble$records_extracted, na.rm = TRUE)

  # Check for errors across all status columns
  status_matrix <- results_tibble |>
    dplyr::select("ocr_status", "metadata_status", "extraction_status", "refinement_status") |>
    as.matrix()

  # A file has an error if ANY of its status columns is not "completed" or "skipped"
  file_has_error <- apply(status_matrix, 1, function(row) {
    any(!row %in% c("completed", "skipped"))
  })

  errors <- sum(file_has_error)

  # Processed successfully = no errors (all steps completed or skipped)
  processed <- nrow(results_tibble) - errors

  # Add attributes
  attr(results_tibble, "start_time") <- start_time
  attr(results_tibble, "end_time") <- end_time
  attr(results_tibble, "duration") <- as.numeric(difftime(end_time, start_time, units = "secs"))
  attr(results_tibble, "total_rows") <- total_rows

  # Store database info - show path if available, otherwise connection class
  if (is.character(db_conn)) {
    attr(results_tibble, "database") <- db_conn
    db_label <- db_conn
  } else {
    attr(results_tibble, "database") <- class(db_conn)[1]
    db_label <- paste0(class(db_conn)[1], " connection")
  }

  # Summary
  # Total files = all files attempted
  # Processed successfully = files where all 4 steps reached completion (completed or skipped)
  # Errors = files where at least one step failed
  cat("\n", strrep("=", 70), "\n")
  cat("PROCESSING COMPLETE\n")
  cat(strrep("=", 70), "\n")
  cat("Total files:", nrow(results_tibble), "\n")
  cat("Processed successfully:", processed, "\n")
  cat("Errors:", errors, "\n")
  cat("Records in database:", total_rows, "\n")
  cat("Duration:", round(attr(results_tibble, "duration"), 2), "seconds\n")
  cat("Database:", db_label, "\n")
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
#' @param run_extraction If TRUE, run extraction step (default: TRUE)
#' @param run_refinement If TRUE, run refinement step (default: TRUE)
#' @param force_reprocess If TRUE, re-run all steps even if outputs exist (default: FALSE)
#' @return List with processing result
#' @keywords internal
process_single_document <- function(pdf_file,
                                    db_conn,
                                    schema_file = NULL,
                                    extraction_prompt_file = NULL,
                                    refinement_prompt_file = NULL,
                                    run_extraction = TRUE,
                                    run_refinement = TRUE,
                                    force_reprocess = FALSE) {

  # Log header
  message(strrep("=", 70))
  message(glue::glue("Processing: {basename(pdf_file)}"))
  message(strrep("=", 70))

  # Initialize status tracking with filename only (all start as 'skipped')
  status_tracking <- list(filename = basename(pdf_file),
                          ocr_status = "skipped",
                          metadata_status = "skipped",
                          extraction_status = "skipped",
                          records_extracted = 0,
                          refinement_status = "skipped")

  # Step 1: OCR Processing
  message("\n[1/4] OCR Processing...")
  ocr_result <- ocr_document(pdf_file, db_conn, force_reprocess)
  status_tracking$document_id <- ocr_result$document_id
  status_tracking$ocr_status <- ocr_result$status
  # Continue if completed or skipped, stop on error
  if(status_tracking$ocr_status != "completed" && status_tracking$ocr_status != "skipped") {
    message(paste("OCR error detected:", status_tracking$ocr_status))
    return(status_tracking)
  }

  # Step 2: Extract Metadata
  message("\n[2/4] Extracting Metadata...")
  metadata_result <- extract_metadata(status_tracking$document_id, db_conn, force_reprocess)
  status_tracking$metadata_status <- metadata_result$status
  # Continue if completed or skipped, stop on error
  if(status_tracking$metadata_status != "completed" && status_tracking$metadata_status != "skipped") {
    message(paste("Metadata extraction error detected:", status_tracking$metadata_status))
    return(status_tracking)
  }

  # Step 3: Extract records
  if (run_extraction) {
    message("\n[3/4] Extracting Records...")
    extraction_result <- extract_records(
      document_id = status_tracking$document_id,
      interaction_db = db_conn,
      force_reprocess = force_reprocess,
      schema_file = schema_file,
      extraction_prompt_file = extraction_prompt_file
    )
    status_tracking$extraction_status <- extraction_result$status
    status_tracking$records_extracted <- extraction_result$records_extracted %||% 0
    # Continue if completed or skipped, stop on error
    if(status_tracking$extraction_status != "completed" && status_tracking$extraction_status != "skipped") {
      message(paste("Extraction error detected:", status_tracking$extraction_status))
      return(status_tracking)
    }
  } else {
    message("\n[3/4] Extracting Records... SKIPPED (run_extraction = FALSE)")
    status_tracking$extraction_status <- "skipped"
    status_tracking$records_extracted <- 0
  }

  # Step 4: Refine records
  if (run_refinement) {
    message("\n[4/4] Refining Records...")
    refinement_result <- refine_records(
      db_conn = db_conn,
      document_id = status_tracking$document_id,
      extraction_prompt_file = extraction_prompt_file,
      schema_file = schema_file,
      refinement_prompt_file = refinement_prompt_file
    )
    status_tracking$refinement_status <- refinement_result$status
    # Continue if completed or skipped, stop on error
    if(status_tracking$refinement_status != "completed" && status_tracking$refinement_status != "skipped") {
      message(paste("Refinement error detected:", status_tracking$refinement_status))
      return(status_tracking)
    }
  } else {
    message("\n[4/4] Refining Records... SKIPPED (run_refinement = FALSE)")
    status_tracking$refinement_status <- "skipped"
  }

  # Get final record count from database (after extraction + refinement)
  final_count <- DBI::dbGetQuery(db_conn,
    "SELECT COUNT(*) as count FROM records WHERE document_id = ?",
    params = list(status_tracking$document_id))$count
  status_tracking$records_extracted <- final_count

  # Summary
  message(strrep("-", 70))
  message(glue::glue("SUCCESS: {status_tracking$records_extracted} records in database"))
  message(strrep("-", 70))

  return(status_tracking)
}
