#' OCR Functions
#'
#' Functions for performing OCR on PDF documents

#' Perform OCR on PDF
#'
#' @param pdf_file Path to PDF
#' @return List with markdown content, images, and raw result
#' @keywords internal
perform_ocr <- function(pdf_file) {
  # Perform OCR using ohseer
  ocr_result <- ohseer::mistral_ocr(pdf_file)

  # Extract and combine markdown from all pages
  markdown <- paste(sapply(ocr_result$pages, function(p) p$markdown), collapse = "\n\n")

  # Extract images from all pages
  images <- lapply(seq_along(ocr_result$pages), function(i) {
    list(
      page_num = i,
      images = ocr_result$pages[[i]]$images
    )
  })

  return(list(markdown = markdown, images = images, raw = ocr_result))
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

    # Save document to database
    document_id <- save_document_to_db(
      db_path = db_conn@dbname,
      file_path = pdf_file,
      metadata = list(
        document_content = ocr_result$markdown,
        ocr_images = jsonlite::toJSON(list(pages = ocr_result$images), auto_unbox = TRUE)
      )
    )

    message(glue::glue("OCR completed: {nchar(ocr_result$markdown)} characters extracted"))
    return(list(
      status = "completed",
      document_id = document_id
    ))
  }, error = function(e) {
    return(list(
      status = paste("OCR failed:", e$message),
      document_id = NA
    ))
  })
}
