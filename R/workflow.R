#' Check if a document should be forced to reprocess
#'
#' @param force_param NULL, TRUE, or integer vector of document_ids
#' @param document_id The document ID to check
#' @return logical
#' @keywords internal
is_forced <- function(force_param, document_id) {
 if (is.null(force_param)) return(FALSE)
 if (isTRUE(force_param)) return(TRUE)
 if (is.numeric(force_param)) return(document_id %in% force_param)
 return(FALSE)
}

#' Determine if a processing step should run
#'
#' @param status Current status value for this step
#' @param data_exists Logical or NULL. If logical, checks for desync
#'   (status="completed" but data missing). Pass NULL to skip desync check.
#' @return logical - TRUE if step should run, FALSE to skip
#' @keywords internal
should_run_step <- function(status, data_exists) {
 # Status not completed - needs to run
 # Handle NULL, NA, or any value other than "completed"
 if (is.null(status) || is.na(status) || status != "completed") return(TRUE)

 # Desync check - status says completed but data is missing
 if (!is.null(data_exists) && !isTRUE(data_exists)) return(TRUE)

 # Status completed and data exists (or no check needed) - skip
 return(FALSE)
}

#' Validate force_reprocess parameter
#'
#' @param param The parameter value to validate
#' @param param_name Name of the parameter for error messages
#' @keywords internal
validate_force_param <- function(param, param_name) {
 if (!is.null(param) && !isTRUE(param) && !is.numeric(param))

   stop(sprintf("%s must be NULL, TRUE, or an integer vector of document_ids", param_name))
}

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
#' @param force_reprocess_ocr Controls OCR reprocessing. NULL (default) uses normal skip logic,
#'   TRUE forces all documents, or an integer vector of document_ids to force specific documents.
#' @param force_reprocess_metadata Controls metadata reprocessing. NULL (default) uses normal skip logic,
#'   TRUE forces all documents, or an integer vector of document_ids to force specific documents.
#' @param force_reprocess_extraction Controls extraction reprocessing. NULL (default) uses normal skip logic,
#'   TRUE forces all documents, or an integer vector of document_ids to force specific documents.
#' @param run_extraction If TRUE, run extraction step to find new records. Default TRUE.
#' @param run_refinement Controls refinement step. NULL (default) skips refinement,
#'   TRUE runs on all documents with records, or an integer vector of document_ids
#'   to refine only specific documents.
#' @param min_similarity Minimum similarity for deduplication (default: 0.9)
#' @param embedding_provider Provider for embeddings when using embedding method (default: "openai")
#' @param similarity_method Method for deduplication similarity: "embedding", "jaccard", or "llm" (default: "llm")
#' @param recursive If TRUE and pdf_path is a directory, search for PDFs in all subdirectories. Default FALSE.
#' @param workers Number of parallel workers. NULL (default) or 1 for sequential processing.
#'   Values > 1 require the crew package and db_conn must be a file path (not a connection object).
#' @param log If TRUE and using parallel processing (workers > 1), write detailed output
#'   to an auto-generated log file (e.g., ecoextract_20240129_143052.log). Default FALSE.
#'   Ignored for sequential processing. Useful for troubleshooting errors.
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
#' # Force re-run OCR for all documents (cascades to metadata and extraction)
#' process_documents("pdfs/", force_reprocess_ocr = TRUE)
#'
#' # Force re-run OCR for specific documents only
#' process_documents("pdfs/", force_reprocess_ocr = c(5L, 12L))
#'
#' # Force re-run metadata only (cascades to extraction)
#' process_documents("pdfs/", force_reprocess_metadata = TRUE)
#'
#' # With custom schema and prompts
#' process_documents("pdfs/", "interactions.db",
#'                   schema_file = "ecoextract/schema.json",
#'                   extraction_prompt_file = "ecoextract/extraction_prompt.md")
#'
#' # With refinement for all documents
#' process_documents("pdfs/", run_refinement = TRUE)
#'
#' # Refinement for specific documents only
#' process_documents("pdfs/", run_refinement = c(5L, 12L))
#'
#' # Skip extraction, refinement only on existing records
#' process_documents("pdfs/", run_extraction = FALSE, run_refinement = TRUE)
#'
#' # Search for PDFs in all subdirectories
#' process_documents("research_papers/", recursive = TRUE)
#'
#' # Process in parallel with 4 workers (requires crew package)
#' process_documents("pdfs/", workers = 4)
#'
#' # Parallel with logging for troubleshooting
#' process_documents("pdfs/", workers = 4, log = TRUE)
#' }
process_documents <- function(pdf_path,
                             db_conn = "ecoextract_records.db",
                             schema_file = NULL,
                             extraction_prompt_file = NULL,
                             refinement_prompt_file = NULL,
                             force_reprocess_ocr = NULL,
                             force_reprocess_metadata = NULL,
                             force_reprocess_extraction = NULL,
                             run_extraction = TRUE,
                             run_refinement = NULL,
                             min_similarity = 0.9,
                             embedding_provider = "openai",
                             similarity_method = "llm",
                             recursive = FALSE,
                             workers = NULL,
                             log = FALSE) {

  # Validate force parameters
  validate_force_param(force_reprocess_ocr, "force_reprocess_ocr")
  validate_force_param(force_reprocess_metadata, "force_reprocess_metadata")
  validate_force_param(force_reprocess_extraction, "force_reprocess_extraction")
  validate_force_param(run_refinement, "run_refinement")

  # Validate workers parameter
  use_parallel <- FALSE
  if (!is.null(workers)) {
    if (!is.numeric(workers) || length(workers) != 1 || workers < 1) {
      stop("workers must be NULL or a positive integer")
    }
    workers <- as.integer(workers)
    if (workers > 1) {
      if (!requireNamespace("crew", quietly = TRUE)) {
        stop("Package 'crew' required for parallel processing. Install with: install.packages('crew')")
      }
      if (inherits(db_conn, "DBIConnection")) {
        stop("Parallel processing requires db_conn to be a file path, not a connection object")
      }
      use_parallel <- TRUE
    }
  }

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
      pdf_files <- list.files(pdf_path, pattern = "\\.pdf$", full.names = TRUE,
                              ignore.case = TRUE, recursive = recursive)
      if (length(pdf_files) == 0) {
        if (recursive) {
          stop("No PDF files found in directory or subdirectories: ", pdf_path)
        } else {
          stop("No PDF files found in directory: ", pdf_path,
               "\n  Use recursive = TRUE to search subdirectories")
        }
      }
      if (recursive) {
        cat("Found", length(pdf_files), "PDF files to process (including subdirectories)\n\n")
      } else {
        cat("Found", length(pdf_files), "PDF files to process\n\n")
      }
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

  # Parse schema to extract and validate fields
  schema_list <- jsonlite::fromJSON(schema_src$path, simplifyVector = FALSE)
  record_schema <- schema_list$properties$records$items
  required_fields <- record_schema[["required"]]
  unique_fields <- record_schema[["x-unique-fields"]]

  # Validate custom schema has required x-unique-fields for deduplication
  if (schema_src$source != "package") {
    if (is.null(unique_fields) || length(unique_fields) == 0) {
      stop(
        "Custom schema is missing 'x-unique-fields' array.\n",
        "This field specifies which fields define record uniqueness for deduplication.\n",
        "Add to your schema at properties > records > items:\n\n",
        '  "x-unique-fields": ["field1", "field2"]\n\n',
        "See README section on Schema Requirements for details."
      )
    }
  }

  # Report configuration
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
    cat("  Required fields:", paste(required_fields, collapse = ", "), "\n")
    cat("  Deduplication key:", paste(unique_fields, collapse = " + "), "\n")
    cat("\n")
  }

  # Handle database connection
  # For parallel: keep as path, workers connect individually
  # For sequential: connect here and pass connection
  db_path <- NULL
  if (!inherits(db_conn, "DBIConnection")) {
    db_path <- db_conn
    # Initialize DB if needed
    if (!file.exists(db_conn)) {
      cat("Initializing new database:", db_conn, "\n")
      init_ecoextract_database(db_conn, schema_file = schema_src$path)
    }
    if (!use_parallel) {
      # Sequential mode: connect now
      db_conn <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
      configure_sqlite_connection(db_conn)
      on.exit(DBI::dbDisconnect(db_conn), add = TRUE)
    }
  }

  # Track timing
  start_time <- Sys.time()

  # Process documents
  results_list <- list()

  if (use_parallel) {
    # Parallel processing with crew
    cat("Starting parallel processing with", workers, "workers\n\n")

    # Initialize log file if logging enabled
    log_file <- NULL
    if (isTRUE(log)) {
      log_file <- sprintf("ecoextract_%s.log", format(Sys.time(), "%Y%m%d_%H%M%S"))
      cat("Logging to:", log_file, "\n\n")
      writeLines(c(
        sprintf("EcoExtract Parallel Processing Log"),
        sprintf("Started: %s", Sys.time()),
        sprintf("Workers: %d", workers),
        sprintf("PDFs: %d", length(pdf_files)),
        strrep("=", 70),
        ""
      ), log_file)
    }

    controller <- crew::crew_controller_local(
      workers = workers,
      seconds_idle = 60
    )
    controller$start()
    on.exit(controller$terminate(), add = TRUE)

    # Push tasks for each PDF
    for (i in seq_along(pdf_files)) {
      controller$push(
        command = ecoextract::process_single_document(
          pdf_file = pdf_file,
          db_conn = db_path,
          schema_file = schema_file,
          extraction_prompt_file = extraction_prompt_file,
          refinement_prompt_file = refinement_prompt_file,
          force_reprocess_ocr = force_reprocess_ocr,
          force_reprocess_metadata = force_reprocess_metadata,
          force_reprocess_extraction = force_reprocess_extraction,
          run_extraction = run_extraction,
          run_refinement = run_refinement,
          min_similarity = min_similarity,
          embedding_provider = embedding_provider,
          similarity_method = similarity_method
        ),
        data = list(
          pdf_file = pdf_files[i],
          db_path = db_path,
          schema_file = schema_src$path,
          extraction_prompt_file = extraction_prompt_file,
          refinement_prompt_file = refinement_prompt_file,
          force_reprocess_ocr = force_reprocess_ocr,
          force_reprocess_metadata = force_reprocess_metadata,
          force_reprocess_extraction = force_reprocess_extraction,
          run_extraction = run_extraction,
          run_refinement = run_refinement,
          min_similarity = min_similarity,
          embedding_provider = embedding_provider,
          similarity_method = similarity_method
        ),
        name = basename(pdf_files[i])
      )
    }

    # Collect results with progress
    completed <- 0
    errors <- 0
    total <- length(pdf_files)

    while (completed < total) {
      result <- controller$pop()
      if (!is.null(result)) {
        completed <- completed + 1
        timestamp <- format(Sys.time(), "%H:%M:%S")

        if (!is.null(result$error)) {
          errors <- errors + 1
          results_list[[completed]] <- list(
            filename = result$name,
            document_id = NA,
            ocr_status = paste("Error:", result$error),
            metadata_status = "skipped",
            extraction_status = "skipped",
            refinement_status = "skipped",
            records_extracted = 0
          )
          cat(sprintf("[%d/%d] %s errored: %s\n",
                      completed, total, result$name, result$error))

          # Log error details
          if (!is.null(log_file)) {
            cat(sprintf("\n[%s] [%d/%d] %s\n", timestamp, completed, total, result$name),
                file = log_file, append = TRUE)
            cat("Status: ERROR\n", file = log_file, append = TRUE)
            cat(sprintf("Error: %s\n", result$error), file = log_file, append = TRUE)
            if (!is.null(result$trace)) {
              cat("Traceback:\n", file = log_file, append = TRUE)
              cat(result$trace, file = log_file, append = TRUE, sep = "\n")
            }
            cat(strrep("-", 70), "\n", file = log_file, append = TRUE)
          }
        } else {
          results_list[[completed]] <- result$result
          cat(sprintf("[%d/%d] %s completed\n",
                      completed, total, result$name))

          # Log success details
          if (!is.null(log_file)) {
            r <- result$result
            cat(sprintf("\n[%s] [%d/%d] %s\n", timestamp, completed, total, result$name),
                file = log_file, append = TRUE)
            cat("Status: COMPLETED\n", file = log_file, append = TRUE)
            cat(sprintf("  OCR: %s\n", r$ocr_status), file = log_file, append = TRUE)
            cat(sprintf("  Metadata: %s\n", r$metadata_status), file = log_file, append = TRUE)
            cat(sprintf("  Extraction: %s\n", r$extraction_status), file = log_file, append = TRUE)
            cat(sprintf("  Refinement: %s\n", r$refinement_status), file = log_file, append = TRUE)
            cat(sprintf("  Records: %d\n", r$records_extracted), file = log_file, append = TRUE)
            cat(strrep("-", 70), "\n", file = log_file, append = TRUE)
          }
        }
      }
      Sys.sleep(0.1)
    }

    # Write log summary
    if (!is.null(log_file)) {
      cat(sprintf("\n%s\nCompleted: %s\nTotal: %d | Success: %d | Errors: %d\n",
                  strrep("=", 70), Sys.time(), total, total - errors, errors),
          file = log_file, append = TRUE)
    }

  } else {
    # Sequential processing
    for (pdf_file in pdf_files) {
      result <- process_single_document(
        pdf_file = pdf_file,
        db_conn = db_conn,
        schema_file = schema_src$path,
        extraction_prompt_file = extraction_prompt_file,
        refinement_prompt_file = refinement_prompt_file,
        force_reprocess_ocr = force_reprocess_ocr,
        force_reprocess_metadata = force_reprocess_metadata,
        force_reprocess_extraction = force_reprocess_extraction,
        run_extraction = run_extraction,
        run_refinement = run_refinement,
        min_similarity = min_similarity,
        embedding_provider = embedding_provider,
        similarity_method = similarity_method
      )
      results_list[[length(results_list) + 1]] <- result
    }
  }

  end_time <- Sys.time()

  # Convert results to tibble
  results_tibble <- tibble::tibble(
    filename = sapply(results_list, function(x) x$filename),
    document_id = sapply(results_list, function(x) rlang::`%||%`(x$document_id, NA)),
    ocr_status = sapply(results_list, function(x) x$ocr_status),
    metadata_status = sapply(results_list, function(x) x$metadata_status),
    extraction_status = sapply(results_list, function(x) x$extraction_status),
    refinement_status = sapply(results_list, function(x) x$refinement_status),
    records_extracted = sapply(results_list, function(x) rlang::`%||%`(x$records_extracted, 0))
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
#' @param force_reprocess_ocr NULL, TRUE, or integer vector of document_ids to force OCR
#' @param force_reprocess_metadata NULL, TRUE, or integer vector of document_ids to force metadata
#' @param force_reprocess_extraction NULL, TRUE, or integer vector of document_ids to force extraction
#' @param run_extraction If TRUE, run extraction step (default: TRUE)
#' @param run_refinement NULL, TRUE, or integer vector of document_ids to run refinement
#' @param min_similarity Minimum cosine similarity for deduplication (default: 0.9)
#' @param embedding_provider Provider for embeddings (default: "openai")
#' @param similarity_method Method for deduplication similarity: "embedding", "jaccard", or "llm" (default: "llm")
#' @return List with processing result
#' @export
process_single_document <- function(pdf_file,
                                    db_conn,
                                    schema_file = NULL,
                                    extraction_prompt_file = NULL,
                                    refinement_prompt_file = NULL,
                                    force_reprocess_ocr = NULL,
                                    force_reprocess_metadata = NULL,
                                    force_reprocess_extraction = NULL,
                                    run_extraction = TRUE,
                                    run_refinement = NULL,
                                    min_similarity = 0.9,
                                    embedding_provider = "openai",
                                    similarity_method = "llm") {

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
  status_tracking <- list(file_name = basename(pdf_file),
                          ocr_status = "skipped",
                          metadata_status = "skipped",
                          extraction_status = "skipped",
                          records_extracted = 0,
                          refinement_status = "skipped")

  # Get or create document record to obtain document_id
  # We need the document_id before we can check statuses or nullify them
  file_hash <- digest::digest(file = pdf_file, algo = "md5")
  existing <- DBI::dbGetQuery(db_conn,
    "SELECT document_id FROM documents WHERE file_hash = ?",
    params = list(file_hash))

  if (nrow(existing) > 0) {
    doc_id <- existing$document_id[1]
  } else {
    # Insert new document record
    DBI::dbExecute(db_conn,
      "INSERT INTO documents (file_name, file_path, file_hash, upload_timestamp)
       VALUES (?, ?, ?, ?)",
      params = list(basename(pdf_file), pdf_file, file_hash, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
    doc_id <- DBI::dbGetQuery(db_conn,
      "SELECT document_id FROM documents WHERE file_hash = ?",
      params = list(file_hash))$document_id[1]
  }
  status_tracking$document_id <- doc_id

  # Nullify statuses for forced documents (handles cascade)
  if (is_forced(force_reprocess_ocr, doc_id)) {
    DBI::dbExecute(db_conn,
      "UPDATE documents SET ocr_status = NULL WHERE document_id = ?",
      params = list(doc_id))
  }
  if (is_forced(force_reprocess_metadata, doc_id)) {
    DBI::dbExecute(db_conn,
      "UPDATE documents SET metadata_status = NULL WHERE document_id = ?",
      params = list(doc_id))
  }
  if (is_forced(force_reprocess_extraction, doc_id)) {
    DBI::dbExecute(db_conn,
      "UPDATE documents SET extraction_status = NULL WHERE document_id = ?",
      params = list(doc_id))
  }

  # Fetch current document state
  doc <- DBI::dbGetQuery(db_conn,
    "SELECT document_id, document_content, ocr_status, metadata_status, extraction_status,
            title, first_author_lastname, publication_year
     FROM documents WHERE document_id = ?",
    params = list(doc_id))

  # Compute data_exists for each step
 ocr_data_exists <- !is.na(doc$document_content[1]) &&
                     !is.null(doc$document_content[1]) &&
                     nchar(doc$document_content[1]) > 0
 metadata_data_exists <- !is.na(doc$title[1]) && !is.null(doc$title[1]) &&
                          !is.na(doc$first_author_lastname[1]) && !is.null(doc$first_author_lastname[1]) &&
                          !is.na(doc$publication_year[1]) && !is.null(doc$publication_year[1])

  # Step 1: OCR Processing
  message("\n[1/4] OCR Processing...")

  if (should_run_step(doc$ocr_status[1], ocr_data_exists)) {
    ocr_result <- ocr_document(pdf_file, db_conn, force_reprocess = TRUE)
    status_tracking$ocr_status <- ocr_result$status

    # Cascade: nullify metadata_status
    DBI::dbExecute(db_conn,
      "UPDATE documents SET metadata_status = NULL WHERE document_id = ?",
      params = list(doc_id))
  } else {
    message(glue::glue("OCR already completed for {basename(pdf_file)}, skipping"))
    status_tracking$ocr_status <- "skipped"
  }

  # Save OCR status to DB
  tryCatch({
    DBI::dbExecute(db_conn,
      "UPDATE documents SET ocr_status = ? WHERE document_id = ?",
      params = list(status_tracking$ocr_status, doc_id))
  }, error = function(e) {
    status_tracking$ocr_status <<- paste("Failure: Could not save status -", e$message)
  })

  # Check for failure before continuing
 failure <- !status_tracking$ocr_status %in% c("skipped", "completed")

  # Step 2: Extract Metadata
  message("\n[2/4] Extracting Metadata...")

  if (!failure) {
    # Re-fetch to get updated metadata_status after potential cascade
    doc <- DBI::dbGetQuery(db_conn,
      "SELECT metadata_status, title, first_author_lastname, publication_year
       FROM documents WHERE document_id = ?",
      params = list(doc_id))
   metadata_data_exists <- !is.na(doc$title[1]) && !is.null(doc$title[1]) &&
                            !is.na(doc$first_author_lastname[1]) && !is.null(doc$first_author_lastname[1]) &&
                            !is.na(doc$publication_year[1]) && !is.null(doc$publication_year[1])

    if (should_run_step(doc$metadata_status[1], metadata_data_exists)) {
      metadata_result <- extract_metadata(document_id = doc_id, db_conn, force_reprocess = TRUE)
      status_tracking$metadata_status <- metadata_result$status

      # Cascade: nullify extraction_status
      DBI::dbExecute(db_conn,
        "UPDATE documents SET extraction_status = NULL WHERE document_id = ?",
        params = list(doc_id))
    } else {
      message("Metadata already exists, skipping")
      status_tracking$metadata_status <- "skipped"
    }
  }

  # Save metadata status to DB
  tryCatch({
    DBI::dbExecute(db_conn,
      "UPDATE documents SET metadata_status = ? WHERE document_id = ?",
      params = list(status_tracking$metadata_status, doc_id))
  }, error = function(e) {
    status_tracking$metadata_status <<- paste("Failure: Could not save status -", e$message)
  })

 failure <- !status_tracking$ocr_status %in% c("skipped", "completed") ||
             !status_tracking$metadata_status %in% c("skipped", "completed")

  # Step 3: Extract records
  message("\n[3/4] Extracting Records...")

  if (run_extraction && !failure) {
    # Re-fetch to get updated extraction_status after potential cascade
    doc <- DBI::dbGetQuery(db_conn,
      "SELECT extraction_status FROM documents WHERE document_id = ?",
      params = list(doc_id))

    # No desync check for extraction (zero records is valid)
    if (should_run_step(doc$extraction_status[1], NULL)) {
      extraction_result <- extract_records(
        document_id = doc_id,
        db_conn = db_conn,
        schema_file = schema_file,
        extraction_prompt_file = extraction_prompt_file,
        min_similarity = min_similarity,
        embedding_provider = embedding_provider,
        similarity_method = similarity_method
      )
      status_tracking$extraction_status <- extraction_result$status
      status_tracking$records_extracted <- rlang::`%||%`(extraction_result$records_extracted, 0)
    } else {
      message("Extraction already completed, skipping")
      status_tracking$extraction_status <- "skipped"
    }
  }

  # Save extraction status to DB
  tryCatch({
    DBI::dbExecute(db_conn,
      "UPDATE documents SET extraction_status = ? WHERE document_id = ?",
      params = list(status_tracking$extraction_status, doc_id))
  }, error = function(e) {
    status_tracking$extraction_status <<- paste("Failure: Could not save status -", e$message)
  })

 failure <- !status_tracking$ocr_status %in% c("skipped", "completed") ||
             !status_tracking$metadata_status %in% c("skipped", "completed") ||
             !status_tracking$extraction_status %in% c("skipped", "completed")

  # Step 4: Refine records (opt-in only)
  message("\n[4/4] Refining Records...")

  if (!failure && is_forced(run_refinement, doc_id)) {
    # Check if records exist
    records_exist <- DBI::dbGetQuery(db_conn,
      "SELECT COUNT(*) > 0 AS has_records FROM records WHERE document_id = ?",
      params = list(doc_id))$has_records[1]

    if (records_exist) {
      refinement_result <- refine_records(
        db_conn = db_conn,
        document_id = doc_id,
        extraction_prompt_file = extraction_prompt_file,
        schema_file = schema_file,
        refinement_prompt_file = refinement_prompt_file
      )
      status_tracking$refinement_status <- refinement_result$status
    } else {
      message("No existing records found. Skipping refinement (no records to refine).")
      status_tracking$refinement_status <- "skipped: no records"
    }
  }

  # Save refinement status to DB
  tryCatch({
    DBI::dbExecute(db_conn,
      "UPDATE documents SET refinement_status = ? WHERE document_id = ?",
      params = list(status_tracking$refinement_status, doc_id))
  }, error = function(e) {
    status_tracking$refinement_status <<- paste("Failure: Could not save status -", e$message)
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
