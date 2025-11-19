#' Complete Document Processing Workflow
#'
#' Process PDFs through the complete pipeline: OCR → Metadata → Extract → Refine
#'
#' @param pdf_path Path to a single PDF file or directory of PDFs
#' @param db_conn Database connection (any DBI backend) or path to SQLite database file.
#'   If a path is provided, creates SQLite database if it doesn't exist.
#'   If a connection is provided, tables must already exist (use \code{init_ecoextract_database()} first).
#' @param schema_file Optional custom schema file
#' @param extraction_prompt_file Optional custom extraction prompt
#' @param refinement_prompt_file Optional custom refinement prompt
#' @param force_reprocess_ocr If TRUE, re-run OCR and delete all data for documents (OCR, metadata, records, status, reasoning). User will be warned. Default FALSE - skips if OCR already done.
#' @param force_reprocess_metadata If TRUE, re-run metadata extraction and overwrite all metadata fields. Default FALSE - skips if metadata already exists.
#' @param run_extraction If TRUE, run extraction step to find new records. Default TRUE.
#' @param run_refinement If TRUE, run refinement step to enhance existing records. Default FALSE.
#' @param min_similarity Minimum similarity for deduplication (default: 0.9)
#' @param embedding_provider Provider for embeddings when using embedding method (default: "openai")
#' @param similarity_method Method for deduplication similarity: "embedding" or "jaccard" (default: "embedding")
#' @return Tibble with processing results
#' @export
#'
#' @examples
#' \dontrun{
#' # Basic usage - process new PDFs
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
#' # Force re-run OCR (WARNING: deletes ALL data for documents - OCR, metadata, records)
#' process_documents("pdfs/", force_reprocess_ocr = TRUE)
#'
#' # Force re-run metadata only (overwrites metadata fields, keeps records)
#' process_documents("pdfs/", force_reprocess_metadata = TRUE)
#'
#' # With custom schema and prompts
#' process_documents("pdfs/", "interactions.db",
#'                   schema_file = "ecoextract/schema.json",
#'                   extraction_prompt_file = "ecoextract/extraction_prompt.md")
#'
#' # With refinement (opt-in)
#' process_documents("pdfs/", run_refinement = TRUE)
#'
#' # Skip extraction, refinement only on existing records
#' process_documents("pdfs/", run_extraction = FALSE, run_refinement = TRUE)
#' }
process_documents <- function(pdf_path,
                             db_conn = "ecoextract_records.db",
                             schema_file = NULL,
                             extraction_prompt_file = NULL,
                             refinement_prompt_file = NULL,
                             force_reprocess_ocr = FALSE,
                             force_reprocess_metadata = FALSE,
                             run_extraction = TRUE,
                             run_refinement = FALSE,
                             min_similarity = 0.9,
                             embedding_provider = "openai",
                             similarity_method = "embedding") {

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

 # Handle database connection - accept either connection object or path
  if (!inherits(db_conn, "DBIConnection")) {
    # Path string - initialize if needed, then connect
    if (!file.exists(db_conn)) {
      cat("Initializing new database:", db_conn, "\n")
      init_ecoextract_database(db_conn, schema_file = schema_src$path)
    }
    db_conn <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    configure_sqlite_connection(db_conn)
    on.exit(DBI::dbDisconnect(db_conn), add = TRUE)
  }

  # Track timing
  start_time <- Sys.time()

  # Process each PDF and collect results
  results_list <- list()

  for (pdf_file in pdf_files) {
    result <- process_single_document(
      pdf_file = pdf_file,
      db_conn = db_conn,
      schema_file = schema_src$path,
      extraction_prompt_file = extraction_prompt_file,
      refinement_prompt_file = refinement_prompt_file,
      force_reprocess_ocr = force_reprocess_ocr,
      force_reprocess_metadata = force_reprocess_metadata,
      run_extraction = run_extraction,
      run_refinement = run_refinement,
      min_similarity = min_similarity,
      embedding_provider = embedding_provider,
      similarity_method = similarity_method
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
#' @param force_reprocess_ocr If TRUE, re-run OCR and delete all data (default: FALSE)
#' @param force_reprocess_metadata If TRUE, re-run metadata extraction (default: FALSE)
#' @param run_extraction If TRUE, run extraction step (default: TRUE)
#' @param run_refinement If TRUE, run refinement step (default: FALSE)
#' @param min_similarity Minimum cosine similarity for deduplication (default: 0.9)
#' @param embedding_provider Provider for embeddings (default: "openai")
#' @param similarity_method Method for deduplication similarity: "embedding" or "jaccard" (default: "embedding")
#' @return List with processing result
#' @keywords internal
process_single_document <- function(pdf_file,
                                    db_conn,
                                    schema_file = NULL,
                                    extraction_prompt_file = NULL,
                                    refinement_prompt_file = NULL,
                                    force_reprocess_ocr = FALSE,
                                    force_reprocess_metadata = FALSE,
                                    run_extraction = TRUE,
                                    run_refinement = FALSE,
                                    min_similarity = 0.9,
                                    embedding_provider = "openai",
                                    similarity_method = "embedding") {

  # Log header
  message(strrep("=", 70))
  message(glue::glue("Processing: {basename(pdf_file)}"))
  message(strrep("=", 70))

  # Handle database connection - accept either connection object or path
  if (!inherits(db_conn, "DBIConnection")) {
    # Path string - initialize if needed, then connect
    if (!file.exists(db_conn)) {
      cat("Initializing new database:", db_conn, "\n")
      init_ecoextract_database(db_conn, schema_file = schema_file)
    }
    db_conn <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    configure_sqlite_connection(db_conn)
    on.exit(DBI::dbDisconnect(db_conn), add = TRUE)
  }

  # Initialize status tracking with filename only (all start as 'skipped')
  status_tracking <- list(filename = basename(pdf_file),
                          ocr_status = "skipped",
                          metadata_status = "skipped",
                          extraction_status = "skipped",
                          records_extracted = 0,
                          refinement_status = "skipped")

  # Step 1: OCR Processing
  message("\n[1/4] OCR Processing...")

  # Run OCR (will skip if document_content exists and force_reprocess=FALSE)
  ocr_result <- ocr_document(pdf_file, db_conn, force_reprocess = force_reprocess_ocr)
  status_tracking$ocr_status <- ocr_result$status
  status_tracking$document_id <- ocr_result$document_id

  # Save status to DB
  status_tracking$ocr_status <- tryCatch({
    DBI::dbExecute(db_conn,
      "UPDATE documents SET ocr_status = ? WHERE document_id = ?",
      params = list(status_tracking$ocr_status, status_tracking$document_id))
    status_tracking$ocr_status
  }, error = function(e) {
    paste("Failure: Could not save status -", e$message)
  })
  
  status_tracking$document_id <- ocr_result$document_id

  # Step 2: Extract Metadata
  message("\n[2/4] Extracting Metadata...")

  failure <- any(!status_tracking[grep("status", names(status_tracking))] %in% c("skipped","completed"))

  # Only run if no failures yet
  if(!failure) {
    # Run metadata extraction (will skip if metadata exists and force_reprocess=FALSE)
    metadata_result <- extract_metadata(document_id = status_tracking$document_id,
                                        db_conn,
                                        force_reprocess = force_reprocess_metadata)
    status_tracking$metadata_status <- metadata_result$status
  }

  # Save status to DB
  status_tracking$metadata_status <- tryCatch({
    DBI::dbExecute(db_conn,
      "UPDATE documents SET metadata_status = ? WHERE document_id = ?",
      params = list(status_tracking$metadata_status, status_tracking$document_id))
    status_tracking$metadata_status
  }, error = function(e) {
    paste("Failure: Could not save status -", e$message)
  }) 

  failure <- any(!status_tracking[grep("status", names(status_tracking))] %in% c("skipped","completed"))

  # Step 3: Extract records
  if (run_extraction && !failure) {
    message("\n[3/4] Extracting Records...")

    extraction_result <- extract_records(
      document_id = status_tracking$document_id,
      db_conn = db_conn,
      force_reprocess = FALSE,
      schema_file = schema_file,
      extraction_prompt_file = extraction_prompt_file,
      min_similarity = min_similarity,
      embedding_provider = embedding_provider,
      similarity_method = similarity_method
    )
    status_tracking$extraction_status <- extraction_result$status
    status_tracking$records_extracted <- extraction_result$records_extracted %||% 0
  }

  # Save status to DB
  status_tracking$extraction_status <- tryCatch({
    DBI::dbExecute(db_conn,
      "UPDATE documents SET extraction_status = ? WHERE document_id = ?",
      params = list(status_tracking$extraction_status, status_tracking$document_id))
    status_tracking$extraction_status
  }, error = function(e) {
    paste("Failure: Could not save status -", e$message)
  })

  failure <- any(!status_tracking[grep("status", names(status_tracking))] %in% c("skipped","completed"))

  # Step 4: Refine records
  if (run_refinement && !failure) {
    message("\n[4/4] Refining Records...")

    existing_records <- DBI::dbGetQuery(db_conn,
      "SELECT COUNT(*) as count FROM records WHERE document_id = ?",
      params = list(status_tracking$document_id))

    if (existing_records$count[1] == 0) {
      message("No existing records found. Skipping refinement (no records to refine).")
      status_tracking$refinement_status <- "skipped: no records"
    } else {
      refinement_result <- refine_records(
        db_conn = db_conn,
        document_id = status_tracking$document_id,
        extraction_prompt_file = extraction_prompt_file,
        schema_file = schema_file,
        refinement_prompt_file = refinement_prompt_file
      )
      status_tracking$refinement_status <- refinement_result$status
    } 
  }

  # Save status to DB
  status_tracking$refinement_status <- tryCatch({
    DBI::dbExecute(db_conn,
      "UPDATE documents SET refinement_status = ? WHERE document_id = ?",
      params = list(status_tracking$refinement_status, status_tracking$document_id))
    status_tracking$refinement_status
  }, error = function(e) {
    paste("Failure: Could not save status -", e$message)
  })

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
