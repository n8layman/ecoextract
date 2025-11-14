#' Data Access Functions
#'
#' Functions for retrieving OCR results, audit data, and extracted records from the database

#' Get OCR Markdown
#'
#' Retrieve OCR markdown text for a document
#'
#' @param document_id Document ID
#' @param db_conn Database connection (any DBI backend) or path to SQLite
#'   database file. Defaults to "ecoextract_records.db"
#' @return Character string with markdown content, or NA if not found
#' @export
#' @examples
#' \dontrun{
#' # Using default SQLite database
#' markdown <- get_ocr_markdown(1)
#'
#' # Using explicit connection
#' db <- DBI::dbConnect(RSQLite::SQLite(), "ecoextract.sqlite")
#' markdown <- get_ocr_markdown(1, db)
#' DBI::dbDisconnect(db)
#' }
get_ocr_markdown <- function(document_id, db_conn = "ecoextract_records.db") {
  # Handle database connection - accept either connection object or path
  if (inherits(db_conn, "DBIConnection")) {
    con <- db_conn
    close_on_exit <- FALSE
  } else {
    con <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    close_on_exit <- TRUE
  }

  if (close_on_exit) {
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }

  get_document_content(document_id, con)
}

#' Get OCR HTML Preview
#'
#' Render OCR results as HTML with embedded images
#'
#' @param document_id Document ID
#' @param db_conn Database connection (any DBI backend) or path to SQLite
#'   database file. Defaults to "ecoextract_records.db"
#' @param page_num Page number to render (default: 1, use "all" for all pages)
#' @return Browsable HTML object for display in RStudio viewer
#' @export
#' @examples
#' \dontrun{
#' # Using default SQLite database
#' html <- get_ocr_html_preview(1)
#' print(html)  # Opens in RStudio viewer
#'
#' # Using explicit connection
#' db <- DBI::dbConnect(RSQLite::SQLite(), "ecoextract.sqlite")
#' html <- get_ocr_html_preview(1, db)
#' print(html)  # Opens in RStudio viewer
#' DBI::dbDisconnect(db)
#' }
get_ocr_html_preview <- function(document_id, db_conn = "ecoextract_records.db", page_num = 1) {
  # Handle database connection - accept either connection object or path
  if (inherits(db_conn, "DBIConnection")) {
    con <- db_conn
    close_on_exit <- FALSE
  } else {
    con <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    close_on_exit <- TRUE
  }

  if (close_on_exit) {
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }

  # Get markdown content
  markdown_content <- get_document_content(document_id, con)

  if (is.na(markdown_content)) {
    stop("No OCR markdown found for document ID: ", document_id)
  }

  # Get images
  result <- DBI::dbGetQuery(con, "
    SELECT ocr_images FROM documents WHERE document_id = ?
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
#' Replace markdown image bibliography with HTML img tags containing base64 data
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

#' Get Documents
#'
#' Retrieve documents from the database
#'
#' @param document_id Document ID to filter by (NULL for all documents)
#' @param db_conn Database connection (any DBI backend) or path to SQLite
#'   database file. Defaults to "ecoextract_records.db"
#' @return Tibble with document metadata
#' @export
#' @examples
#' \dontrun{
#' # Using default SQLite database
#' all_docs <- get_documents()
#' doc <- get_documents(document_id = 1)
#'
#' # Using explicit connection
#' db <- DBI::dbConnect(RSQLite::SQLite(), "ecoextract.sqlite")
#' all_docs <- get_documents(db_conn = db)
#' doc <- get_documents(document_id = 1, db_conn = db)
#' DBI::dbDisconnect(db)
#' }
get_documents <- function(document_id = NULL, db_conn = "ecoextract_records.db") {
  # Handle database connection - accept either connection object or path
  if (inherits(db_conn, "DBIConnection")) {
    con <- db_conn
    close_on_exit <- FALSE
  } else {
    con <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    close_on_exit <- TRUE
  }

  if (close_on_exit) {
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }

  tryCatch({
    if (is.null(document_id)) {
      # Get all documents
      result <- DBI::dbGetQuery(con, "SELECT * FROM documents") |>
        tibble::as_tibble()
    } else {
      # Get specific document
      result <- DBI::dbGetQuery(con, "
        SELECT * FROM documents WHERE document_id = ?
      ", params = list(document_id)) |>
        tibble::as_tibble()
    }
    result
  }, error = function(e) {
    message("Error retrieving documents: ", e$message)
    tibble::tibble()
  })
}

#' Get Records
#'
#' Retrieve extracted records from the database
#'
#' @param document_id Document ID to filter by (NULL for all records)
#' @param db_conn Database connection (any DBI backend) or path to SQLite
#'   database file. Defaults to "ecoextract_records.db"
#' @return Tibble with records
#' @export
#' @examples
#' \dontrun{
#' # Using default SQLite database
#' all_records <- get_records()
#' doc_records <- get_records(document_id = 1)
#'
#' # Using explicit connection
#' db <- DBI::dbConnect(RSQLite::SQLite(), "ecoextract.sqlite")
#' all_records <- get_records(db_conn = db)
#' doc_records <- get_records(document_id = 1, db_conn = db)
#' DBI::dbDisconnect(db)
#' }
get_records <- function(document_id = NULL, db_conn = "ecoextract_records.db") {
  # Handle database connection - accept either connection object or path
  if (inherits(db_conn, "DBIConnection")) {
    con <- db_conn
    close_on_exit <- FALSE
  } else {
    con <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    close_on_exit <- TRUE
  }

  if (close_on_exit) {
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }

  tryCatch({
    if (is.null(document_id)) {
      # Get all records
      result <- DBI::dbGetQuery(con, "SELECT * FROM records") |>
        tibble::as_tibble()
    } else {
      # Get records for specific document
      result <- DBI::dbGetQuery(con, "
        SELECT * FROM records WHERE document_id = ?
      ", params = list(document_id)) |>
        tibble::as_tibble()
    }
    result
  }, error = function(e) {
    message("Error retrieving records: ", e$message)
    tibble::tibble()
  })
}

#' Export Database
#'
#' Export records joined with document metadata
#'
#' @param document_id Optional document ID to filter by (NULL for all documents)
#' @param db_conn Database connection (any DBI backend) or path to SQLite
#'   database file. Defaults to "ecoextract_records.db"
#' @param include_ocr If TRUE, include OCR content in export (default: FALSE)
#' @param simple If TRUE, exclude processing metadata columns (default: FALSE)
#' @param filename Optional path to save as CSV file (if NULL, returns tibble only)
#' @return Tibble with records joined to document metadata, or invisibly if saved to file
#' @export
#' @examples
#' \dontrun{
#' # Get all records with metadata as tibble
#' data <- export_db()
#'
#' # Get records for specific document
#' data <- export_db(document_id = 1)
#'
#' # Export to CSV
#' export_db(filename = "extracted_data.csv")
#'
#' # Include OCR content
#' data <- export_db(include_ocr = TRUE)
#'
#' # Simplified output (no processing metadata)
#' data <- export_db(simple = TRUE)
#' }
export_db <- function(document_id = NULL,
                      db_conn = "ecoextract_records.db",
                      include_ocr = FALSE,
                      simple = FALSE,
                      filename = NULL) {
  # Handle database connection
  if (inherits(db_conn, "DBIConnection")) {
    con <- db_conn
    close_on_exit <- FALSE
  } else {
    con <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    close_on_exit <- TRUE
  }

  if (close_on_exit) {
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }

  tryCatch({
    # Build WHERE clause
    where_clause <- if (!is.null(document_id)) {
      paste0("WHERE d.document_id = ", document_id)
    } else {
      ""
    }

    # Build SELECT - include all columns then reorder
    select_cols <- c(
      "d.document_id", "d.file_name", "d.file_path",
      "d.title", "d.authors", "d.first_author_lastname", "d.publication_year",
      "d.journal", "d.volume", "d.issue", "d.pages",
      "d.doi", "d.issn", "d.publisher", "d.bibliography",
      "d.records_extracted",
      "d.ocr_status", "d.metadata_status", "d.extraction_status", "d.refinement_status"
    )

    if (include_ocr) {
      select_cols <- c(select_cols, "d.document_content", "d.ocr_images")
    }

    # Execute query with all columns
    query <- paste0(
      "SELECT d.*, r.* ",
      "FROM records r ",
      "JOIN documents d ON r.document_id = d.document_id ",
      where_clause
    )

    result <- DBI::dbGetQuery(con, query) |>
      tibble::as_tibble()

    # Reorder columns logically if data exists
    if (nrow(result) > 0) {
      # Define fixed document metadata columns in logical order
      doc_cols_ordered <- c(
        # Document identification
        "document_id", "file_name", "file_path",
        # Publication metadata
        "title", "authors", "first_author_lastname", "publication_year",
        "journal", "volume", "issue", "pages", "doi", "issn", "publisher", "bibliography",
        # Extraction summary and status
        "records_extracted",
        "ocr_status", "metadata_status", "extraction_status", "refinement_status"
      )

      # Add OCR content if requested
      if (include_ocr) {
        doc_cols_ordered <- c(doc_cols_ordered, "document_content")
      }

      # Get all document columns that exist in result (in our specified order)
      doc_cols_present <- intersect(doc_cols_ordered, names(result))

      # Get all records columns (in database order - user controls this via schema)
      all_doc_cols <- c(doc_cols_ordered, "file_hash", "file_size", "upload_timestamp",
                        "ocr_images", "extraction_reasoning", "refinement_reasoning")
      record_cols <- setdiff(names(result), all_doc_cols)

      # Final order: document columns (logical order) + records columns (database order)
      col_order <- c(doc_cols_present, record_cols)

      # Select and reorder
      result <- result |>
        dplyr::select(dplyr::any_of(col_order))
    }

    # Filter columns if simple mode
    if (simple && nrow(result) > 0) {
      # Remove processing metadata columns
      metadata_cols <- c(
        "id", "extraction_timestamp", "llm_model_version", "prompt_hash",
        "fields_changed_count", "flagged_for_review", "review_reason",
        "human_edited", "rejected", "deleted_by_user"
      )
      result <- result |>
        dplyr::select(-dplyr::any_of(metadata_cols))
    }

    # Save to CSV if filename provided
    if (!is.null(filename)) {
      readr::write_csv(result, filename)
      message("Exported ", nrow(result), " records to ", filename)
      return(invisible(result))
    }

    return(result)

  }, error = function(e) {
    message("Error exporting database: ", e$message)
    tibble::tibble()
  })
}

