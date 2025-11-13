#' OCR Functions
#'
#' Functions for performing OCR on PDF documents

#' Perform OCR on PDF
#'
#' @param pdf_file Path to PDF
#' @return List with markdown content, images, and raw result
#' @keywords internal
perform_ocr <- function(pdf_file) {
  # Perform OCR using Tensorlake via ohseer
  ocr_result <- ohseer::tensorlake_ocr(pdf_file)

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

#' OCR Document and Save to Database (Atomic)
#'
#' Performs OCR on PDF and saves document to database
#'
#' @param pdf_file Path to PDF file
#' @param db_conn Database connection
#' @param force_reprocess If TRUE, re-run OCR even if document_content already exists (default: FALSE)
#' @return List with status ("completed"/"skipped"/<error message>) and document_id
#' @export
ocr_document <- function(pdf_file, db_conn, force_reprocess = FALSE) {

  # Check if already processed (document exists with valid OCR content)
  if (!force_reprocess) {
    existing <- DBI::dbGetQuery(db_conn,
      "SELECT id, document_content FROM documents WHERE file_path = ?",
      params = list(pdf_file))

    if (nrow(existing) > 0 &&
        !is.na(existing$document_content[1]) &&
        nchar(existing$document_content[1]) > 0) {
      message(glue::glue("OCR already completed for {basename(pdf_file)}, skipping (force_reprocess=FALSE)"))
      return(list(
        status = "skipped",
        document_id = existing$id[1]
      ))
    }
  }

  tryCatch({
    message(glue::glue("Performing OCR on {basename(pdf_file)}..."))
    ocr_result <- perform_ocr(pdf_file)

    # Save document to database with JSON content
    document_id <- save_document_to_db(
      db_conn = db_conn,
      file_path = pdf_file,
      metadata = list(
        document_content = ocr_result$json_content
      )
    )

    message(glue::glue(
      "OCR completed: {length(ocr_result$pages)} pages extracted"
    ))
    list(
      status = "completed",
      document_id = document_id
    )
  }, error = function(e) {
    list(
      status = paste("OCR failed:", e$message),
      document_id = NA
    )
  })
}
