#' Data Access Functions
#'
#' Functions for retrieving OCR results, audit data, and extracted records from the database

#' Get OCR Markdown
#'
#' Retrieve OCR markdown text for a document
#'
#' @param document_id Document ID
#' @param db_conn Database connection
#' @return Character string with markdown content, or NA if not found
#' @export
#' @examples
#' \dontrun{
#' db <- DBI::dbConnect(RSQLite::SQLite(), "ecoextract.sqlite")
#' markdown <- get_ocr_markdown(1, db)
#' DBI::dbDisconnect(db)
#' }
get_ocr_markdown <- function(document_id, db_conn) {
  get_document_content(document_id, db_conn)
}

#' Get OCR Audit
#'
#' Retrieve OCR quality audit results for a document
#'
#' @param document_id Document ID
#' @param db_conn Database connection
#' @return OCR audit data (JSON string), or NA if not found
#' @export
#' @examples
#' \dontrun{
#' db <- DBI::dbConnect(RSQLite::SQLite(), "ecoextract.sqlite")
#' audit <- get_ocr_audit(1, db)
#' DBI::dbDisconnect(db)
#' }
get_ocr_audit <- function(document_id, db_conn) {
  tryCatch({
    result <- DBI::dbGetQuery(db_conn, "
      SELECT ocr_audit FROM documents WHERE id = ?
    ", params = list(document_id))

    if (nrow(result) == 0 || is.null(result$ocr_audit) || result$ocr_audit == "") {
      return(NA)
    }

    return(result$ocr_audit[1])
  }, error = function(e) {
    message("Error retrieving OCR audit: ", e$message)
    return(NA)
  })
}

#' Get OCR HTML Preview
#'
#' Render OCR results as HTML with embedded images
#'
#' @param document_id Document ID
#' @param db_conn Database connection
#' @param page_num Page number to render (default: 1, use "all" for all pages)
#' @return Browsable HTML object for display in RStudio viewer
#' @export
#' @examples
#' \dontrun{
#' db <- DBI::dbConnect(RSQLite::SQLite(), "ecoextract.sqlite")
#' html <- get_ocr_html_preview(1, db)
#' print(html)  # Opens in RStudio viewer
#' DBI::dbDisconnect(db)
#' }
get_ocr_html_preview <- function(document_id, db_conn, page_num = 1) {
  # Get markdown content
  markdown_content <- get_document_content(document_id, db_conn)

  if (is.na(markdown_content)) {
    stop("No OCR markdown found for document ID: ", document_id)
  }

  # Get images
  result <- DBI::dbGetQuery(db_conn, "
    SELECT ocr_images FROM documents WHERE id = ?
  ", params = list(document_id))

  if (nrow(result) == 0) {
    stop("Document not found: ", document_id)
  }

  # If no images, just render markdown
  if (is.null(result$ocr_images) || result$ocr_images == "" || is.na(result$ocr_images)) {
    html_content <- markdown::mark_html(markdown_content)
    styled_html <- sprintf(
      '<div style="font-family: sans-serif; max-width: 900px; margin: 20px auto; padding: 20px; line-height: 1.6;">
        <style>
          img { max-width: 100%%; height: auto; display: block; margin: 20px 0; }
          pre { background: #f5f5f5; padding: 10px; border-radius: 4px; overflow-x: auto; }
          code { background: #f5f5f5; padding: 2px 4px; border-radius: 2px; }
          table { border-collapse: collapse; width: 100%%; margin: 20px 0; }
          th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
          th { background-color: #f5f5f5; }
        </style>
        <div style="background: #fff3cd; border: 1px solid #ffc107; padding: 10px; margin-bottom: 20px; border-radius: 4px;">
          <strong>Note:</strong> No images found for this document. Showing markdown-only preview.
        </div>
        %s
      </div>',
      html_content
    )
    return(htmltools::browsable(htmltools::HTML(styled_html)))
  }

  # Parse images JSON
  images_data <- jsonlite::fromJSON(result$ocr_images, simplifyVector = FALSE)

  # Process markdown to embed images
  processed_markdown <- embed_images_in_markdown(markdown_content, images_data, page_num)

  # Convert to HTML
  html_content <- markdown::mark_html(processed_markdown)

  # Wrap in styled div
  styled_html <- sprintf(
    '<div style="font-family: sans-serif; max-width: 900px; margin: 20px auto; padding: 20px; line-height: 1.6;">
      <style>
        img { max-width: 100%%; height: auto; display: block; margin: 20px 0; }
        pre { background: #f5f5f5; padding: 10px; border-radius: 4px; overflow-x: auto; }
        code { background: #f5f5f5; padding: 2px 4px; border-radius: 2px; }
        table { border-collapse: collapse; width: 100%%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f5f5f5; }
      </style>
      %s
    </div>',
    html_content
  )

  return(htmltools::browsable(htmltools::HTML(styled_html)))
}

#' Embed Images in Markdown (Internal Helper)
#'
#' Replace markdown image references with HTML img tags containing base64 data
#'
#' @param markdown_text Markdown text
#' @param images_data Parsed images JSON object
#' @param page_num Page number to process (default: 1, "all" for all pages)
#' @return Processed markdown with embedded images
#' @keywords internal
embed_images_in_markdown <- function(markdown_text, images_data, page_num = 1) {
  if (is.null(images_data$pages) || length(images_data$pages) == 0) {
    return(markdown_text)
  }

  processed_text <- markdown_text

  # Process each page
  for (page_idx in seq_along(images_data$pages)) {
    # Skip if not the requested page (unless page_num == "all")
    if (page_num != "all" && page_idx != page_num) {
      next
    }

    page_data <- images_data$pages[[page_idx]]

    if (is.null(page_data$images) || length(page_data$images) == 0) {
      next
    }

    # Process each image in the page
    for (i in seq_along(page_data$images)) {
      image_data <- page_data$images[[i]]

      # Get the base64 string
      base64_string <- image_data$image_base64

      # Ensure it has data URI prefix
      if (grepl("^data:image/", base64_string)) {
        data_uri <- base64_string
      } else {
        data_uri <- paste0("data:image/png;base64,", base64_string)
      }

      # Create HTML img tag
      img_html <- sprintf('<img src="%s" style="max-width: 100%%; height: auto;" alt="Page %d, Image %d" />',
                          data_uri, page_idx, i)

      # Image index (0-based in Mistral's naming: img-0.jpeg, img-1.jpeg, etc.)
      img_idx <- i - 1

      # Try multiple markdown image reference patterns

      # Pattern 1: ![img-{idx}.jpeg](img-{idx}.jpeg) or similar extensions
      pattern1 <- sprintf("!\\[img-%d\\.[^]]+\\]\\(img-%d\\.[^)]+\\)", img_idx, img_idx)
      if (grepl(pattern1, processed_text)) {
        processed_text <- gsub(pattern1, img_html, processed_text)
        next
      }

      # Pattern 2: ![image{i}](...) or ![image{i}]
      pattern2 <- sprintf("!\\[image%d\\](\\([^)]*\\))?", i)
      if (grepl(pattern2, processed_text)) {
        processed_text <- gsub(pattern2, img_html, processed_text)
        next
      }

      # Pattern 3: ![{i}](...) or ![{i}]
      pattern3 <- sprintf("!\\[%d\\](\\([^)]*\\))?", i)
      if (grepl(pattern3, processed_text)) {
        processed_text <- gsub(pattern3, img_html, processed_text)
        next
      }

      # Pattern 4: ![](...) - replace the i-th occurrence
      pattern4 <- "!\\[\\]\\([^)]*\\)"
      matches <- gregexpr(pattern4, processed_text)
      if (matches[[1]][1] != -1 && length(matches[[1]]) >= i) {
        match_pos <- matches[[1]][i]
        match_len <- attr(matches[[1]], "match.length")[i]

        before <- substr(processed_text, 1, match_pos - 1)
        after <- substr(processed_text, match_pos + match_len, nchar(processed_text))
        processed_text <- paste0(before, img_html, after)
      }
    }
  }

  return(processed_text)
}

#' Get Records
#'
#' Retrieve extracted records from the database
#'
#' @param document_id Document ID to filter by (NULL for all records)
#' @param db_conn Database connection
#' @return Tibble with records
#' @export
#' @examples
#' \dontrun{
#' db <- DBI::dbConnect(RSQLite::SQLite(), "ecoextract.sqlite")
#'
#' # Get all records
#' all_records <- get_records(db_conn = db)
#'
#' # Get records for specific document
#' doc_records <- get_records(document_id = 1, db_conn = db)
#'
#' DBI::dbDisconnect(db)
#' }
get_records <- function(document_id = NULL, db_conn) {
  tryCatch({
    if (is.null(document_id)) {
      # Get all records
      result <- DBI::dbGetQuery(db_conn, "SELECT * FROM records") |>
        tibble::as_tibble()
    } else {
      # Get records for specific document
      result <- DBI::dbGetQuery(db_conn, "
        SELECT * FROM records WHERE document_id = ?
      ", params = list(document_id)) |>
        tibble::as_tibble()
    }
    return(result)
  }, error = function(e) {
    message("Error retrieving records: ", e$message)
    return(tibble::tibble())
  })
}
