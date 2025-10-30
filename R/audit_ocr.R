#' OCR Quality Audit
#'
#' Reads document from DB, performs quality audit using LLM, saves audit back to DB
#'
#' @param document_id Document ID in database
#' @param db_conn Database connection
#' @param model LLM model for OCR audit (default: "anthropic/claude-sonnet-4-20250514")
#' @return List with status ("completed"/"skipped"/<error message>)
#' @export
audit_ocr <- function(document_id, db_conn, model = "anthropic/claude-sonnet-4-20250514") {

  tryCatch({
    # Read document content from database
    markdown_text <- get_document_content(document_id, db_conn)

    if (is.na(markdown_text) || is.null(markdown_text)) {
      return(list(status = "No document content found in database"))
    }

    message("Performing OCR quality audit...")

    # Load OCR audit prompt
    audit_prompt <- get_ocr_audit_prompt()

    message(glue::glue("Calling {model} for OCR audit"))

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

    # Build audit results
    ocr_audit <- list(
      original_markdown = markdown_text,
      audited_markdown = as.character(audit_result),
      audit_notes = "OCR reviewed for common errors"
    )

    # Update document with audit results
    DBI::dbExecute(db_conn,
      "UPDATE documents SET ocr_audit = ? WHERE id = ?",
      params = list(
        jsonlite::toJSON(ocr_audit, auto_unbox = TRUE),
        document_id
      )
    )

    message("OCR audit completed")
    return(list(status = "completed"))
  }, error = function(e) {
    return(list(status = paste("OCR audit failed:", e$message)))
  })
}
