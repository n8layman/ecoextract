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
    configure_sqlite_connection(con)
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
    configure_sqlite_connection(con)
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
    configure_sqlite_connection(con)
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
    configure_sqlite_connection(con)
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
    configure_sqlite_connection(con)
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

    # Get column names to build explicit SELECT
    doc_cols <- DBI::dbListFields(con, "documents")
    rec_cols <- setdiff(DBI::dbListFields(con, "records"), "document_id")

    # Build explicit column list with aliases
    select_list <- c(
      paste0("d.", doc_cols),
      paste0("r.", rec_cols)
    )

    # Execute query with explicit columns to avoid duplicates
    query <- paste0(
      "SELECT ", paste(select_list, collapse = ", "), " ",
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
      # Note: document_content must be in all_doc_cols even when include_ocr = FALSE
      # to prevent it from appearing in record_cols
      all_doc_cols <- c(doc_cols_ordered, "document_content", "file_hash", "file_size",
                        "upload_timestamp", "ocr_images", "extraction_reasoning",
                        "refinement_reasoning")
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
        "extraction_timestamp", "llm_model_version", "prompt_hash",
        "fields_changed_count", "human_edited", "deleted_by_user"
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

#' Diff Records Between Original and Edited Versions
#'
#' Compares two record dataframes and categorizes changes by record_id.
#'
#' @param original_df Original records dataframe (before edits)
#' @param records_df Edited records dataframe (after edits)
#' @return List with: $modified (record_ids), $added (dataframe), $deleted (record_ids)
#' @keywords internal
diff_records <- function(original_df, records_df) {
  # Metadata columns to exclude from comparison

  metadata_cols <- c(
    "document_id", "record_id", "extraction_timestamp",
    "llm_model_version", "prompt_hash", "fields_changed_count",
    "human_edited", "deleted_by_user"
  )

  orig_ids <- original_df$record_id

orig_ids <- orig_ids[!is.na(orig_ids)]
  new_ids <- records_df$record_id
  new_ids <- new_ids[!is.na(new_ids)]

  added_ids <- setdiff(new_ids, orig_ids)
  deleted_ids <- setdiff(orig_ids, new_ids)
  common_ids <- intersect(orig_ids, new_ids)

  # Check which common records have schema field changes
  schema_cols <- setdiff(names(original_df), metadata_cols)
  schema_cols <- intersect(schema_cols, names(records_df))

  modified_ids <- character(0)
  for (rid in common_ids) {
    orig_row <- original_df[original_df$record_id == rid, schema_cols, drop = FALSE]
    new_row <- records_df[records_df$record_id == rid, schema_cols, drop = FALSE]

    # Compare values (handle NA equality)
    changed <- !mapply(function(a, b) {
      identical(as.character(a), as.character(b))
    }, orig_row, new_row)

    if (any(changed)) {
      modified_ids <- c(modified_ids, rid)
    }
  }

  list(
    modified = modified_ids,
    added = records_df[records_df$record_id %in% added_ids, , drop = FALSE],
    deleted = deleted_ids
  )
}

#' Save Document After Human Review
#'
#' Updates document metadata with review timestamp and saves modified records,
#' marking changed rows as human_edited. Designed for Shiny app review workflows.
#'
#' @param document_id Document ID to update
#' @param records_df Updated records dataframe (from Shiny editor)
#' @param original_df Original records dataframe (before edits, for diff). If NULL,
#'   only updates reviewed_at timestamp without modifying records.
#' @param db_conn Database connection or path to SQLite database file
#' @param ... Additional metadata fields to update on the document
#' @return Invisibly returns the document_id
#' @export
#' @examples
#' \dontrun{
#' # In Shiny app "Accept" button handler
#' save_document(
#'   document_id = input$document_select,
#'   records_df = edited_records(),
#'   original_df = original_records(),
#'   db_conn = db_path
#' )
#' }
save_document <- function(document_id, records_df, original_df = NULL,
                          db_conn = "ecoextract_records.db", ...) {
  # Handle database connection
  if (inherits(db_conn, "DBIConnection")) {
    con <- db_conn
    close_on_exit <- FALSE
  } else {
    con <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    configure_sqlite_connection(con)
    close_on_exit <- TRUE
  }

  if (close_on_exit) {
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }

  # Validate document exists
  existing <- DBI::dbGetQuery(con,
    "SELECT document_id FROM documents WHERE document_id = ?",
    params = list(document_id))
  if (nrow(existing) == 0) {
    stop("Document ID ", document_id, " not found")
  }

  # Begin transaction
  DBI::dbBegin(con)
  tryCatch({
    # Update document metadata with reviewed_at + any ... args
    dots <- list(...)
    reviewed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    if (length(dots) > 0) {
      # Build dynamic UPDATE for additional fields
      field_names <- names(dots)
      set_clause <- paste0(field_names, " = ?", collapse = ", ")
      query <- paste0("UPDATE documents SET reviewed_at = ?, ", set_clause,
                      " WHERE document_id = ?")
      params <- c(list(reviewed_at), unname(dots), list(document_id))
    } else {
      query <- "UPDATE documents SET reviewed_at = ? WHERE document_id = ?"
      params <- list(reviewed_at, document_id)
    }
    DBI::dbExecute(con, query, params = params)

    # If original_df provided, diff and update records
    if (!is.null(original_df) && nrow(original_df) > 0) {
      changes <- diff_records(original_df, records_df)

      # Handle deleted records
      if (length(changes$deleted) > 0) {
        placeholders <- paste(rep("?", length(changes$deleted)), collapse = ", ")
        DBI::dbExecute(con,
          paste0("UPDATE records SET deleted_by_user = ? WHERE document_id = ? AND record_id IN (", placeholders, ")"),
          params = c(list(reviewed_at, document_id), as.list(changes$deleted)))
      }

      # Handle modified records
      if (length(changes$modified) > 0) {
        # Get schema columns (non-metadata)
        metadata_cols <- c(
          "document_id", "record_id", "extraction_timestamp",
          "llm_model_version", "prompt_hash", "fields_changed_count",
          "human_edited", "deleted_by_user"
        )
        schema_cols <- setdiff(names(records_df), metadata_cols)

        for (rid in changes$modified) {
          new_row <- records_df[records_df$record_id == rid, , drop = FALSE]
          set_parts <- paste0(schema_cols, " = ?", collapse = ", ")
          query <- paste0("UPDATE records SET ", set_parts,
                          ", human_edited = ? WHERE document_id = ? AND record_id = ?")

          # Build params - convert list columns to JSON
          params <- lapply(schema_cols, function(col) {
            val <- new_row[[col]]
            if (is.list(val)) {
              jsonlite::toJSON(val[[1]], auto_unbox = TRUE)
            } else {
              val
            }
          })
          params <- c(params, list(reviewed_at, document_id, rid))
          DBI::dbExecute(con, query, params = params)
        }
      }

      # Handle added records
      if (nrow(changes$added) > 0) {
        # Get existing record metadata for the document
        doc_meta <- DBI::dbGetQuery(con,
          "SELECT first_author_lastname, publication_year FROM documents WHERE document_id = ?",
          params = list(document_id))

        # Get max sequence number for this document
        max_seq <- DBI::dbGetQuery(con,
          "SELECT COUNT(*) as n FROM records WHERE document_id = ?",
          params = list(document_id))$n

        for (i in seq_len(nrow(changes$added))) {
          new_row <- changes$added[i, , drop = FALSE]

          # Generate record_id if missing
          if (is.na(new_row$record_id) || new_row$record_id == "") {
            new_row$record_id <- generate_record_id(
              doc_meta$first_author_lastname %||% "Unknown",
              doc_meta$publication_year %||% format(Sys.Date(), "%Y"),
              max_seq + i
            )
          }

          # Prepare insert
          metadata_cols <- c(
            "extraction_timestamp", "llm_model_version", "prompt_hash",
            "fields_changed_count", "deleted_by_user"
          )
          insert_cols <- setdiff(names(new_row), metadata_cols)
          insert_cols <- c(insert_cols, "document_id", "human_edited", "extraction_timestamp",
                           "llm_model_version", "prompt_hash")

          placeholders <- paste(rep("?", length(insert_cols)), collapse = ", ")
          query <- paste0("INSERT INTO records (", paste(insert_cols, collapse = ", "),
                          ") VALUES (", placeholders, ")")

          # Build params
          params <- lapply(setdiff(insert_cols, c("document_id", "human_edited",
                                                   "extraction_timestamp", "llm_model_version",
                                                   "prompt_hash")), function(col) {
            val <- new_row[[col]]
            if (is.list(val)) {
              jsonlite::toJSON(val[[1]], auto_unbox = TRUE)
            } else {
              val
            }
          })
          params <- c(params, list(
            document_id,
            reviewed_at,  # human_edited timestamp
            reviewed_at,  # extraction_timestamp
            "human_review",  # llm_model_version
            "human_review"   # prompt_hash
          ))

          DBI::dbExecute(con, query, params = params)
        }
      }
    }

    DBI::dbCommit(con)
  }, error = function(e) {
    DBI::dbRollback(con)
    stop("Error saving document: ", e$message)
  })

  invisible(document_id)
}

