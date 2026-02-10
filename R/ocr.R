#' OCR Functions
#'
#' Functions for performing OCR on PDF documents

#' Perform OCR on PDF
#'
#' @param pdf_file Path to PDF
#' @param max_wait_seconds Maximum seconds to wait for OCR completion (default: 60)
#' @return List with markdown content, images, and raw result
#' @keywords internal
perform_ocr <- function(pdf_file, max_wait_seconds = 60) {
  # Perform OCR using Tensorlake via ohseer
  ocr_result <- ohseer::tensorlake_ocr(pdf_file, max_wait_seconds = max_wait_seconds)

  # Extract pages as structured JSON
  pages <- ohseer::tensorlake_extract_pages(ocr_result)

  # Convert pages to JSON string for storage
  json_content <- jsonlite::toJSON(pages, auto_unbox = TRUE, pretty = TRUE)

  list(
    json_content = json_content,
    pages = pages,
    raw = ocr_result
  )
}

#' OCR Document and Save to Database
#'
#' Performs OCR on PDF and saves document to database.
#' Skip logic is handled by the workflow - this function always runs OCR when called.
#'
#' @param pdf_file Path to PDF file
#' @param db_conn Database connection
#' @param force_reprocess Ignored (kept for backward compatibility). Skip logic handled by workflow.
#' @param max_wait_seconds Maximum seconds to wait for OCR completion (default: 60)
#' @return List with status ("completed"/<error message>) and document_id
#' @keywords internal
ocr_document <- function(pdf_file, db_conn, force_reprocess = TRUE, max_wait_seconds = 60) {

 document_id <- NA

  # Handle database connection - accept either connection object or path
  if (!inherits(db_conn, "DBIConnection")) {
    # Path string - initialize if needed, then connect
    if (!file.exists(db_conn)) {
      cat("Initializing new database:", db_conn, "\n")
      init_ecoextract_database(db_conn)
    }
    db_conn <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    configure_sqlite_connection(db_conn)
    on.exit(DBI::dbDisconnect(db_conn), add = TRUE)
  }

  # Run OCR
  ocr_response <- tryCatch({
    message(glue::glue("Performing OCR on {basename(pdf_file)}..."))
    ocr_result <- perform_ocr(pdf_file, max_wait_seconds = max_wait_seconds)

    # Save document to database with JSON content
    saved_id <- save_document_to_db(
      db_conn = db_conn,
      file_path = pdf_file,
      overwrite = TRUE,
      metadata = list(
        document_content = ocr_result$json_content
      )
    )

    message(glue::glue(
      "OCR completed: {length(ocr_result$pages)} pages extracted"
    ))
    list(status = "completed", document_id = saved_id)
  }, error = function(e) {
    list(status = paste("OCR failed:", e$message), document_id = NA)
  })

  return(list(status = ocr_response$status, document_id = ocr_response$document_id))
}
