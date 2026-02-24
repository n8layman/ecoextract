#' OCR Functions
#'
#' Functions for performing OCR on PDF documents

#' Perform OCR on PDF
#'
#' @param pdf_file Path to PDF
#' @param provider OCR provider to use (default: "tensorlake")
#' @param timeout Maximum seconds to wait for OCR completion (default: 300)
#' @return List with markdown content, images, and raw result
#' @keywords internal
perform_ocr <- function(pdf_file, provider = "tensorlake", timeout = 300) {
  # Use unified ohseer interface
  result <- ohseer::ohseer_ocr(
    file_path = pdf_file,
    provider = provider,
    timeout = timeout
  )

  # Strip image_base64 fields from pages before storing - base64 blobs bloat
  # document_content and waste LLM context without adding extraction value.
  # image_annotation (text description) is preserved.
  pages <- lapply(result$pages, function(page) {
    if (!is.null(page$images) && length(page$images) > 0) {
      page$images <- lapply(page$images, function(img) img[names(img) != "image_base64"])
    }
    page
  })

  # Extract pages and convert to JSON
  json_content <- jsonlite::toJSON(pages, auto_unbox = TRUE, pretty = TRUE)

  list(
    json_content = json_content,
    pages = pages,
    raw = result$raw,
    provider_used = result$provider,  # Actual provider that succeeded
    error_log = result$error_log      # Failed attempts (if any)
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
#' @param provider OCR provider to use (default: "tensorlake")
#' @param timeout Maximum seconds to wait for OCR completion (default: 300)
#' @param max_wait_seconds Deprecated. Use timeout instead.
#' @return List with status ("completed"/<error message>) and document_id
#' @keywords internal
ocr_document <- function(pdf_file, db_conn, force_reprocess = TRUE, provider = "tensorlake", timeout = 300, max_wait_seconds = NULL) {

 document_id <- NA

  # Handle deprecated parameter
  if (!is.null(max_wait_seconds)) {
    warning("Parameter 'max_wait_seconds' is deprecated. Use 'timeout' instead.", call. = FALSE)
    timeout <- max_wait_seconds
  }

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
    providers_msg <- if (length(provider) > 1) {
      paste0("providers: ", paste(provider, collapse = ", "))
    } else {
      paste0("provider: ", provider)
    }
    message(glue::glue("Performing OCR with {providers_msg} on {basename(pdf_file)}..."))
    ocr_result <- perform_ocr(pdf_file, provider = provider, timeout = timeout)

    # Save document to database with JSON content and provider tracking
    saved_id <- save_document_to_db(
      db_conn = db_conn,
      file_path = pdf_file,
      overwrite = TRUE,
      metadata = list(
        document_content = ocr_result$json_content,
        ocr_provider = ocr_result$provider_used,  # Use actual provider that succeeded
        ocr_log = if (!is.na(ocr_result$error_log)) ocr_result$error_log else NA
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
