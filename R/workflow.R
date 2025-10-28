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
#' process_document("pdfs/")
#'
#' # Process a single PDF with custom database
#' process_document("paper.pdf", "my_interactions.db")
#'
#' # With custom schema and prompts
#' process_document("pdfs/", "interactions.db",
#'                  schema_file = "ecoextract/schema.json",
#'                  extraction_prompt_file = "ecoextract/extraction_prompt.md")
#' }
process_document <- function(pdf_path,
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

  # Process each PDF
  results <- list(
    total_files = length(pdf_files),
    processed = 0,
    skipped = 0,
    errors = 0,
    total_interactions = 0,
    details = list()
  )

  for (pdf_file in pdf_files) {
    result <- process_single_document(
      pdf_file = pdf_file,
      db_conn = db_conn,
      schema_file = schema_file,
      extraction_prompt_file = extraction_prompt_file,
      refinement_prompt_file = refinement_prompt_file,
      skip_existing = skip_existing
    )

    results$details[[basename(pdf_file)]] <- result

    if (result$status == "success") {
      results$processed <- results$processed + 1
      results$total_interactions <- results$total_interactions + result$interaction_count
    } else if (result$status == "skipped") {
      results$skipped <- results$skipped + 1
    } else {
      results$errors <- results$errors + 1
    }
  }

  # Summary
  cat("\n", strrep("=", 70), "\n")
  cat("PROCESSING COMPLETE\n")
  cat(strrep("=", 70), "\n")
  cat("Total files:", results$total_files, "\n")
  cat("Processed:", results$processed, "\n")
  cat("Skipped:", results$skipped, "\n")
  cat("Errors:", results$errors, "\n")
  cat("Total interactions extracted:", results$total_interactions, "\n")
  cat("Database:", db_path, "\n")
  cat(strrep("=", 70), "\n\n")

  invisible(results)
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

  cat("\n", strrep("=", 70), "\n")
  cat("Processing:", basename(pdf_file), "\n")
  cat(strrep("=", 70), "\n")

  tryCatch({
    # Check if already processed
    if (skip_existing) {
      existing <- DBI::dbGetQuery(db_conn,
                                  "SELECT document_id FROM documents WHERE file_path = ?",
                                  params = list(pdf_file))
      if (nrow(existing) > 0) {
        cat("SKIPPED: Already processed (use skip_existing = FALSE to reprocess)\n")
        return(list(status = "skipped", interaction_count = 0))
      }
    }

    # Step 1: OCR Processing
    cat("\n[1/4] OCR Processing...\n")
    ocr_result <- perform_ocr(pdf_file)

    # Step 2: OCR Audit
    cat("\n[2/4] OCR Quality Audit...\n")
    ocr_audit <- perform_ocr_audit(ocr_result$markdown)

    # Step 3: Save document to database
    document_id <- add_document_to_database(
      db_conn = db_conn,
      file_path = pdf_file,
      markdown_content = ocr_result$markdown,
      ocr_audit = ocr_audit
    )

    # Step 4: Extract interactions
    cat("\n[3/4] Extracting Interactions...\n")
    extraction_result <- extract_records(
      document_id = document_id,
      document_content = ocr_result$markdown,
      ocr_audit = ocr_audit,
      schema_file = schema_file,
      extraction_prompt_file = extraction_prompt_file
    )

    if (!extraction_result$success || nrow(extraction_result$interactions) == 0) {
      cat("No interactions extracted\n")
      return(list(status = "success", interaction_count = 0))
    }

    cat("Extracted", nrow(extraction_result$interactions), "interactions\n")

    # Step 5: Refine interactions
    cat("\n[4/4] Refining Interactions...\n")
    refinement_result <- refine_records(
      interactions = extraction_result$interactions,
      markdown_text = ocr_result$markdown,
      ocr_audit = ocr_audit,
      document_id = document_id,
      schema_file = schema_file,
      refinement_prompt_file = refinement_prompt_file
    )

    # Use refined interactions if refinement succeeded
    final_interactions <- if (refinement_result$success) {
      cat("Refined to", nrow(refinement_result$interactions), "interactions\n")
      refinement_result$interactions
    } else {
      cat("Refinement failed, using original extraction\n")
      extraction_result$interactions
    }

    # Step 6: Save to database
    save_records_to_db(
      db_path = db_conn@dbname,
      document_id = document_id,
      interactions_df = final_interactions,
      metadata = list(
        model = extraction_result$model,
        prompt_hash = extraction_result$prompt_hash
      )
    )

    cat("\n", strrep("-", 70), "\n")
    cat("SUCCESS:", nrow(final_interactions), "interactions saved to database\n")
    cat(strrep("-", 70), "\n")

    return(list(
      status = "success",
      interaction_count = nrow(final_interactions),
      document_id = document_id
    ))

  }, error = function(e) {
    cat("\nERROR:", e$message, "\n")
    return(list(
      status = "error",
      error_message = e$message,
      interaction_count = 0
    ))
  })
}

#' Perform OCR on PDF
#'
#' Currently a placeholder - integrate with ohseer package for actual OCR
#'
#' @param pdf_file Path to PDF
#' @return List with markdown content
#' @keywords internal
perform_ocr <- function(pdf_file) {
  # Perform OCR using ohseer
  ocr_result <- ohseer::mistral_ocr(pdf_file)
  return(ocr_result)
}

#' Perform OCR Quality Audit
#'
#' Reviews OCR output for common errors using an LLM
#'
#' @param markdown_text Markdown content from OCR
#' @param model Provider and model in format "provider/model" (default: "anthropic/claude-sonnet-4-20250514")
#' @return List with audit results including corrected markdown and error log
#' @export
perform_ocr_audit <- function(markdown_text, model = "anthropic/claude-sonnet-4-20250514") {

  # Load OCR audit prompt
  audit_prompt <- get_ocr_audit_prompt()

  cat("Calling", model, "for OCR audit\n")

  # Initialize audit chat
  audit_chat <- ellmer::chat(
    name = model,
    system_prompt = audit_prompt,
    echo = "none"
  )

  # Create audit context
  audit_context <- glue::glue(
    "Please review the following OCR output for common errors:\n\n{markdown_text}"
  )

  # Execute audit
  audit_result <- audit_chat$chat(audit_context)

  cat("OCR audit completed\n")

  # Return audit results
  list(
    original_markdown = markdown_text,
    audited_markdown = as.character(audit_result),
    audit_notes = "OCR reviewed for common errors"
  )
}

#' Add Document to Database
#'
#' @param db_conn Database connection
#' @param file_path Path to original PDF
#' @param markdown_content Markdown from OCR
#' @param ocr_audit Audit results
#' @return document_id
#' @keywords internal
add_document_to_database <- function(db_conn, file_path, markdown_content, ocr_audit = NULL) {
  # Insert document
  DBI::dbExecute(db_conn,
    "INSERT INTO documents (file_path, file_name, markdown_content, ocr_status, ocr_audit)
     VALUES (?, ?, ?, ?, ?)",
    params = list(
      file_path,
      basename(file_path),
      markdown_content,
      "completed",
      if (!is.null(ocr_audit)) jsonlite::toJSON(ocr_audit, auto_unbox = TRUE) else NA
    )
  )

  # Get the document_id
  document_id <- DBI::dbGetQuery(db_conn, "SELECT last_insert_rowid() as id")$id

  # Log the process
  log_processing_step(db_conn@dbname, document_id, "ocr", "completed", "OCR processing completed")

  return(document_id)
}
