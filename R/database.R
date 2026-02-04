#' Database Functions for EcoExtract Package
#'
#' Standalone database operations for ecological interaction storage

#' Configure SQLite connection for optimal concurrency
#'
#' Sets PRAGMA options to prevent database locked errors and enable
#' Write-Ahead Logging (WAL) for better concurrent access.
#'
#' @param con SQLite database connection
#' @return The connection object (invisibly)
#' @keywords internal
configure_sqlite_connection <- function(con) {
  # Set busy timeout to 30 seconds (retry on locked database)
  # Increased from 10s to support parallel processing
  DBI::dbExecute(con, "PRAGMA busy_timeout = 30000")

  # Enable WAL mode for better concurrent read/write performance
  # WAL allows readers and writers to operate concurrently
  # This is persistent on the database file (only needs to be set once)
  DBI::dbExecute(con, "PRAGMA journal_mode = WAL")

  invisible(con)
}

#' Normalize array fields based on schema definition (schema-agnostic)
#'
#' Ensures that fields defined as arrays in the schema are properly formatted,
#' even if the LLM returns scalar values. Works with any schema.
#'
#' @param df Dataframe with extracted records
#' @param schema_list Parsed JSON schema (from jsonlite::fromJSON)
#' @return Normalized dataframe with proper array formatting
#' @keywords internal
normalize_array_fields <- function(df, schema_list) {
  if (nrow(df) == 0) return(df)

  # Extract field definitions from schema
  if (!("properties" %in% names(schema_list) &&
        "records" %in% names(schema_list$properties))) {
    # No schema structure, return as-is
    return(df)
  }

  records_schema <- schema_list$properties$records
  if (!("items" %in% names(records_schema) &&
        "properties" %in% names(records_schema$items))) {
    return(df)
  }

  field_properties <- records_schema$items$properties
  required_fields <- rlang::`%||%`(records_schema$items$required, character(0))

  # Identify which fields should be arrays
  array_fields <- names(field_properties)[
    sapply(field_properties, function(prop) {
      type <- prop$type
      if (is.null(type)) return(FALSE)
      # Handle both "array" and ["array", "null"]
      if (length(type) > 1) {
        "array" %in% type
      } else {
        type == "array"
      }
    })
  ]

  # Normalize each array field
  for (field in array_fields) {
    if (!field %in% names(df)) next

    for (i in 1:nrow(df)) {
      value <- df[[field]][[i]]

      # Check if value is missing/null
      is_missing <- is.null(value) ||
                   (is.atomic(value) && length(value) == 1 && is.na(value)) ||
                   (is.atomic(value) && length(value) == 0)

      if (is_missing) {
        # Check if field is required
        if (field %in% required_fields) {
          stop(glue::glue(
            "Required field '{field}' is missing in record {i}. ",
            "LLM must return a value for this field."
          ))
        }
        # Optional field - keep as NULL/NA
        next
      }

      # Value exists - ensure it's a list (for JSON conversion)
      # If it's a scalar (character/numeric/etc), wrap it in a list
      if (is.atomic(value) && !is.list(value)) {
        df[[field]][[i]] <- list(value)
      }
    }
  }

  return(df)
}

#' Initialize EcoExtract database
#' @param db_conn Database connection (any DBI backend) or path to SQLite database file
#' @param schema_file Optional path to JSON schema file (determines record columns)
#' @return NULL (creates database with required tables)
#' @export
init_ecoextract_database <- function(db_conn = "ecoextract_results.sqlite", schema_file = NULL) {
  # Accept either a connection object or a path string
  if (inherits(db_conn, "DBIConnection")) {
    con <- db_conn
    close_on_exit <- FALSE
  } else {
    # Path string - create SQLite connection
    if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("RSQLite", quietly = TRUE)) {
      stop("DBI and RSQLite packages required for SQLite database operations")
    }

    # Create database directory if needed
    db_dir <- dirname(db_conn)
    if (!dir.exists(db_dir) && db_dir != ".") {
      dir.create(db_dir, recursive = TRUE)
    }

    con <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    configure_sqlite_connection(con)
    close_on_exit <- TRUE
  }

  tryCatch({
    # Create documents table
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS documents (
        document_id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_hash TEXT UNIQUE NOT NULL,
        file_size INTEGER,
        upload_timestamp TEXT NOT NULL,

        -- Publication metadata
        title TEXT,
        first_author_lastname TEXT,
        authors TEXT,  -- JSON array of author names
        publication_year INTEGER,
        doi TEXT,
        journal TEXT,
        volume TEXT,
        issue TEXT,
        pages TEXT,
        issn TEXT,
        publisher TEXT,
        bibliography TEXT,  -- JSON array of bibliography citations

        -- Content storage
        document_content TEXT,  -- OCR markdown results
        ocr_images TEXT,        -- OCR images (JSON array of base64 images)

        -- Reasoning logs
        extraction_reasoning TEXT,  -- Reasoning from extraction step
        refinement_reasoning TEXT,  -- Reasoning from refinement step

        -- Step status tracking
        ocr_status TEXT,            -- NULL | 'completed' | 'skipped' | 'OCR failed: <msg>'
        metadata_status TEXT,       -- NULL | 'completed' | 'skipped' | 'Metadata extraction failed: <msg>'
        extraction_status TEXT,     -- NULL | 'completed' | 'skipped' | 'Extraction failed: <msg>'
        refinement_status TEXT,     -- NULL | 'completed' | 'skipped' | 'Refinement failed: <msg>'

        -- Extraction summary
        records_extracted INTEGER DEFAULT 0,  -- Total number of records extracted from this document

        -- Human review tracking
        reviewed_at TEXT  -- Timestamp when document was human-reviewed (NULL = not reviewed)
      )
    ")

    # Load schema using priority order (explicit > project ecoextract/ > wd > package)
    schema_path <- load_config_file(schema_file, "schema.json", "extdata", return_content = FALSE)
    schema_json <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
    schema_json_list <- jsonlite::fromJSON(schema_json, simplifyVector = FALSE)

    # Create records table with dynamic schema
    schema_columns <- get_record_columns_sql(schema_json_list)
    record_table_sql <- paste0("
      CREATE TABLE IF NOT EXISTS records (
        document_id INTEGER NOT NULL,
        record_id TEXT NOT NULL,
        ", schema_columns, "

        -- Processing metadata
        extraction_timestamp TEXT NOT NULL,
        llm_model_version TEXT NOT NULL,
        prompt_hash TEXT NOT NULL,
        fields_changed_count INTEGER DEFAULT 0,
        human_edited TEXT,  -- NULL = not edited, timestamp = when edited
        deleted_by_user TEXT,  -- NULL = not deleted, timestamp = when deleted

        PRIMARY KEY (document_id, record_id),
        FOREIGN KEY (document_id) REFERENCES documents (document_id)
      )
    ")
    DBI::dbExecute(con, record_table_sql)

    # Create indexes for performance
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_documents_hash ON documents (file_hash)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_records_document ON records (document_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_records_record ON records (record_id)")

    if (is.character(db_conn)) {
      cat("EcoExtract database initialized:", db_conn, "\n")
    } else {
      cat("EcoExtract database initialized\n")
    }

  }, error = function(e) {
    cat("Error initializing EcoExtract database:", e$message, "\n")
    stop(e)
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(con)
    }
  })
}

#' Get record table column definitions as SQL
#' @param schema_json_list Parsed JSON schema to generate columns from
#' @return Character string with column definitions
get_record_columns_sql <- function(schema_json_list) {
  if (is.null(schema_json_list)) {
    stop("schema_json_list is required - no schema provided")
  }
  paste0(generate_columns_from_json_schema(schema_json_list), ",")
}

#' Save or reprocess a document in the EcoExtract database
#'
#' Inserts a new document row into the `documents` table, automatically computing file hash if not provided.
#' Optionally, if `overwrite = TRUE`, any existing document with the same file hash is deleted (including associated records),
#' and the new row preserves the old `document_id`.
#'
#' @param db_conn A DBI connection object or a path to an SQLite database file.
#' @param file_path Path to the PDF or document file to store.
#' @param file_hash Optional precomputed file hash (MD5). If `NULL`, it is computed automatically from the file.
#' @param metadata A named list of document metadata. Recognized keys include:
#'   \describe{
#'     \item{title}{Document title.}
#'     \item{first_author_lastname}{Last name of first author.}
#'     \item{publication_year}{Year of publication.}
#'     \item{doi}{DOI of the document.}
#'     \item{journal}{Journal name.}
#'     \item{document_content}{OCR or processed content.}
#'     \item{ocr_images}{OCR images (as JSON array or similar).}
#'   }
#' @param overwrite Logical; if `TRUE`, any existing row with the same file hash is deleted and the new row preserves the old `document_id`.
#'
#' @return The `document_id` of the inserted or replaced row, or `NULL` if insertion fails.
#' @keywords internal
#' @examples
#' \dontrun{
#' db <- "ecoextract_results.sqlite"
#' save_document_to_db(db, "example.pdf", metadata = list(title = "My Paper"), overwrite = TRUE)
#' }
save_document_to_db <- function(db_conn, file_path, file_hash = NULL, metadata = list(), overwrite = FALSE) {
  
  # Safe null/NA coalescing
  `%||NA%` <- function(x, y) {
    if (is.null(x) || length(x) == 0 || (is.atomic(x) && all(is.na(x)))) y else x
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

  # Compute file hash and basic file info
  if (is.null(file_hash)) file_hash <- digest::digest(file_path, file = TRUE, algo = "md5")
  file_size <- if (file.exists(file_path)) as.numeric(file.info(file_path)$size) else NA_integer_
  file_name <- basename(file_path)
  timestamp <- as.character(Sys.time())

  # Handle overwrite: drop existing row by hash if requested
  doc_id <- NULL
  if (overwrite) {
    existing <- DBI::dbGetQuery(db_conn, "SELECT document_id FROM documents WHERE file_hash = ?", params = list(file_hash))
    if (nrow(existing) > 0) {
      doc_id <- existing$document_id[1]
      DBI::dbExecute(db_conn, "DELETE FROM records WHERE document_id = ?", params = list(doc_id))
      DBI::dbExecute(db_conn, "DELETE FROM documents WHERE document_id = ?", params = list(doc_id))
    }
  }

  # Prepare metadata in correct order
  meta_keys <- c("title", "first_author_lastname", "publication_year",
                 "doi", "journal", "document_content", "ocr_images")
  metadata_complete <- lapply(meta_keys, function(k) rlang::`%||%`(metadata[[k]], NA))

  # Combine with file info
  params <- c(list(file_name, file_path, file_hash, file_size, timestamp), metadata_complete)

  # Insert new row (autoincrement)
  DBI::dbExecute(db_conn, "
    INSERT INTO documents (
      file_name, file_path, file_hash, file_size, upload_timestamp,
      title, first_author_lastname, publication_year, doi, journal,
      document_content, ocr_images
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ", params = params)

  # Get the rowid of the inserted row
  last_id <- DBI::dbGetQuery(db_conn, "SELECT last_insert_rowid() AS rowid")$rowid

  # If old_id existed, overwrite document_id with old_id
  if (!is.null(doc_id)) {
    DBI::dbExecute(db_conn, "UPDATE documents SET document_id = ? WHERE rowid = ?", params = list(doc_id, last_id))
  } else {
    doc_id <- last_id
  }

  return(doc_id)
}

#' Save publication metadata to EcoExtract database (internal)
#' 
#' Updates existing document metadata fields that are currently NULL/NA/empty.
#' Optionally overwrites all metadata if `overwrite = TRUE`.
#' 
#' @param document_id Document ID to update
#' @param db_conn Database connection or path to SQLite database
#' @param metadata Named list with metadata fields
#' @param overwrite Logical, if TRUE will overwrite all existing fields
#' @return Document ID
#' @keywords internal
save_metadata_to_db <- function(document_id, db_conn, metadata = list(), overwrite = FALSE) {

  # Safe null/NA coalescing
  `%||NA%` <- function(x, y) {
    if (is.null(x) || length(x) == 0 || (is.atomic(x) && all(is.na(x)))) y else x
  }

  # Handle connection
  if (!inherits(db_conn, "DBIConnection")) {
    con <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    configure_sqlite_connection(con)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  } else {
    con <- db_conn
  }

  # Ensure document exists
  existing <- DBI::dbGetQuery(con, "SELECT * FROM documents WHERE document_id = ?", params = list(document_id))
  if (nrow(existing) == 0) stop("Document ID ", document_id, " not found")

   # Handle overwrite: drop existing row by hash if requested
  if (overwrite) {
      DBI::dbExecute(con, "DELETE FROM records WHERE document_id = ?", params = list(document_id))
      DBI::dbExecute(con, "DELETE FROM documents WHERE document_id = ?", params = list(document_id))
    }

  # Define all possible metadata columns
  meta_keys <- c(
    "title", "first_author_lastname", "authors", "publication_year",
    "doi", "journal", "volume", "issue", "pages", "issn", "publisher", "bibliography"
  )

  # Fill missing keys with NA
  metadata_complete <- unname(sapply(meta_keys, function(k) metadata[[k]] %||NA% NA))
  params <- c(metadata_complete, document_id)

  # Build the SET clause dynamically
  set_clause <- glue::glue_collapse(
    if (overwrite) {
      glue::glue("{meta_keys} = ?")
    } else {
      glue::glue("{meta_keys} = COALESCE(?, {meta_keys})")
    },
    sep = ", "
  )

  # Build full SQL
  sql <- glue::glue("
    UPDATE documents
    SET {set_clause}
    WHERE document_id = ?
  ")

  # Execute query
  DBI::dbExecute(con, sql, params = params)

  return(document_id)
}

#' Save records to EcoExtract database (internal)
#' @param db_path Path to database file
#' @param document_id Document ID
#' @param interactions_df Dataframe of records
#' @param metadata Processing metadata
#' @param schema_list Optional parsed JSON schema for array normalization
#' @return TRUE if successful
#' @keywords internal
save_records_to_db <- function(db_path, document_id, interactions_df, metadata = list(), schema_list = NULL, mode = "insert") {
  if (nrow(interactions_df) == 0) return(invisible(NULL))

  # Validate mode parameter
  if (!mode %in% c("insert", "update")) {
    stop("mode must be either 'insert' (extraction) or 'update' (refinement)")
  }

  # Normalize array fields based on schema (schema-agnostic)
  if (!is.null(schema_list)) {
    interactions_df <- normalize_array_fields(interactions_df, schema_list)
  }

  # Accept either a path (string) or a connection object
  if (inherits(db_path, "DBIConnection")) {
    con <- db_path
    close_on_exit <- FALSE
  } else {
    con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    configure_sqlite_connection(con)
    close_on_exit <- TRUE
  }

  if (close_on_exit) {
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }

  # Handle record IDs - mix of existing (valid) and new (null/invalid) records
  # Valid IDs: Match pattern "Author_2023_1_r1" format (from refinement preserving existing records)
  # Invalid IDs: Don't match pattern, are NA, or are null (from extraction or refinement's new records)

  if ("record_id" %in% names(interactions_df) && nrow(interactions_df) > 0) {
    # Check each ID for validity
    valid_pattern <- "^[A-Za-z]+_[0-9]+_[0-9]+_r[0-9]+$"
    is_valid <- !is.na(interactions_df$record_id) &
                grepl(valid_pattern, interactions_df$record_id)

    valid_count <- sum(is_valid)
    invalid_count <- sum(!is_valid)

    if (valid_count > 0 && invalid_count > 0) {
      message(glue::glue("Mixed IDs: {valid_count} existing (preserved), {invalid_count} new (generating)"))
    } else if (valid_count > 0) {
      message(glue::glue("Preserving existing record IDs for {valid_count} records"))
    } else {
      message(glue::glue("Generating record IDs for {invalid_count} new records"))
    }

    # Only generate IDs for records with invalid/missing IDs
    if (invalid_count > 0) {
      # Get publication metadata
      doc_meta <- DBI::dbGetQuery(con,
        "SELECT first_author_lastname, publication_year FROM documents WHERE document_id = ?",
        params = list(document_id))

      author_lastname <- if (nrow(doc_meta) > 0 && !is.na(doc_meta$first_author_lastname[1])) {
        doc_meta$first_author_lastname[1]
      } else if ("first_author_lastname" %in% names(interactions_df) && !is.na(interactions_df$first_author_lastname[1])) {
        interactions_df$first_author_lastname[1]
      } else {
        "Unknown"
      }

      publication_year <- if (nrow(doc_meta) > 0 && !is.na(doc_meta$publication_year[1])) {
        doc_meta$publication_year[1]
      } else if ("publication_year" %in% names(interactions_df) && !is.na(interactions_df$publication_year[1])) {
        interactions_df$publication_year[1]
      } else {
        as.integer(format(Sys.Date(), "%Y"))
      }

      # Generate IDs only for records that need them
      # Get existing max sequence number to avoid conflicts
      existing_ids <- DBI::dbGetQuery(con,
        "SELECT record_id FROM records WHERE document_id = ?",
        params = list(document_id))$record_id

      max_seq <- 0
      if (length(existing_ids) > 0) {
        # Extract sequence numbers from existing IDs (format: Author_Year_Paper_rN)
        seqs <- as.integer(sub(".*_r([0-9]+)$", "\\1", existing_ids))
        max_seq <- max(seqs, na.rm = TRUE)
      }

      # Generate new IDs starting after max existing
      new_id_count <- 0
      for (i in which(!is_valid)) {
        new_id_count <- new_id_count + 1
        interactions_df$record_id[i] <- paste0(author_lastname, "_", publication_year, "_1_r", max_seq + new_id_count)
      }
    }
  } else {
    # No record_id column or empty dataframe - generate all IDs
    doc_meta <- DBI::dbGetQuery(con,
      "SELECT first_author_lastname, publication_year FROM documents WHERE document_id = ?",
      params = list(document_id))

    author_lastname <- if (nrow(doc_meta) > 0 && !is.na(doc_meta$first_author_lastname[1])) {
      doc_meta$first_author_lastname[1]
    } else {
      "Unknown"
    }

    publication_year <- if (nrow(doc_meta) > 0 && !is.na(doc_meta$publication_year[1])) {
      doc_meta$publication_year[1]
    } else {
      as.integer(format(Sys.Date(), "%Y"))
    }

    interactions_df <- add_record_ids(interactions_df, author_lastname, publication_year)
    message(glue::glue("Generated record IDs for {nrow(interactions_df)} records"))
  }

  # Add required metadata columns
  interactions_df$document_id <- as.integer(document_id)
  interactions_df$extraction_timestamp <- as.character(Sys.time())
  interactions_df$llm_model_version <- rlang::`%||%`(metadata$model, "unknown")
  interactions_df$prompt_hash <- rlang::`%||%`(metadata$prompt_hash, "unknown")

  # Get database column names dynamically
  db_columns <- DBI::dbListFields(con, "records")

  # Add missing columns with NA values (must be same length as dataframe)
  num_rows <- nrow(interactions_df)
  for (col in db_columns) {
    if (!col %in% names(interactions_df)) {
      interactions_df[[col]] <- rep(NA, num_rows)
    }
  }

  # Filter to only include columns that exist in database (in correct order)
  interactions_clean <- interactions_df |>
    dplyr::select(dplyr::all_of(db_columns)) |>
    as.data.frame()  # Convert to data.frame for easier column manipulation

  # Convert list columns to JSON strings
  list_cols <- names(interactions_clean)[sapply(interactions_clean, is.list)]
  for (col in list_cols) {
    col_data <- interactions_clean[[col]]
    result <- character(length(col_data))

    for (i in seq_along(col_data)) {
      x <- col_data[[i]]

      # Handle NULL or empty
      if (is.null(x) || length(x) == 0) {
        result[i] <- NA_character_
        next
      }

      # If it's a data.frame (common from ellmer), convert to JSON
      if (is.data.frame(x)) {
        if (nrow(x) == 0) {
          result[i] <- NA_character_
        } else {
          result[i] <- jsonlite::toJSON(x, auto_unbox = TRUE)
        }
        next
      }

      # If it's a list or vector with multiple elements, convert to JSON
      if (is.list(x) || length(x) > 1) {
        result[i] <- jsonlite::toJSON(x, auto_unbox = FALSE)
        next
      }

      # Otherwise convert to character
      result[i] <- as.character(x)
    }
    interactions_clean[[col]] <- result
  }

  # human_edited and deleted_by_user are timestamps (NULL = not edited/deleted)
  # Ensure they're NA/NULL for new records from extraction

  # ellmer handles schema-defined types (integers, strings, etc.) correctly
  # SQLite will auto-coerce types as needed when inserting

  # Save records based on mode
  # - insert: Always insert new records (for extraction)
  # - update: Only update existing records (for refinement)
  # Wrap in transaction to prevent write conflicts

  DBI::dbBegin(con)
  tryCatch({
    if (mode == "insert") {
      # Insert mode: Simply append all records (extraction already deduplicated)
      DBI::dbWriteTable(con, "records", interactions_clean, append = TRUE, row.names = FALSE)
    } else if (mode == "update") {
      # Update mode: Only update existing records (for refinement)
      updated_count <- 0
      skipped_count <- 0

      for (i in 1:nrow(interactions_clean)) {
        row <- interactions_clean[i, ]

        # Update existing record (only if not human_edited and not rejected)
        cols_to_update <- setdiff(names(row), c("document_id", "record_id"))
        set_clause <- paste(paste0(cols_to_update, " = ?"), collapse = ", ")

        update_sql <- paste0(
          "UPDATE records SET ", set_clause,
          " WHERE document_id = ? AND record_id = ? AND human_edited IS NULL AND deleted_by_user IS NULL"
        )

        params <- unname(c(as.list(row[cols_to_update]), list(row$document_id, row$record_id)))
        rows_affected <- DBI::dbExecute(con, update_sql, params = params)

        if (rows_affected > 0) {
          updated_count <- updated_count + rows_affected
        } else {
          # Record doesn't exist or is protected - skip
          skipped_count <- skipped_count + 1
        }
      }

      if (skipped_count > 0) {
        message(glue::glue("Skipped {skipped_count} records (not found or protected)"))
      }
    }
    DBI::dbCommit(con)
  }, error = function(e) {
    DBI::dbRollback(con)
    stop("Error saving records: ", e$message)
  })

  message(glue::glue("Saved {nrow(interactions_clean)} records to database"))
  invisible(NULL)
}

#' Get database statistics
#' @param db_conn Database connection or path to database file
#' @return List with database statistics
#' @export
get_db_stats <- function(db_conn) {
  # Accept either a connection object or a path string
  if (inherits(db_conn, "DBIConnection")) {
    con <- db_conn
    close_on_exit <- FALSE
  } else {
    # Path string - check existence
    if (!file.exists(db_conn)) {
      return(list(documents = 0, records = 0, message = "Database not found"))
    }
    con <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    configure_sqlite_connection(con)
    close_on_exit <- TRUE
  }

  tryCatch({
    doc_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM documents")$n
    record_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM records")$n

    return(list(
      documents = doc_count,
      records = record_count,
      message = paste("Database contains", doc_count, "documents and", record_count, "records")
    ))

  }, error = function(e) {
    return(list(documents = 0, records = 0, message = paste("Database error:", e$message)))
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(con)
    }
  })
}


#' Extract field definitions from JSON schema
#' @param schema_json_list Parsed JSON schema as list
#' @return Named list with field names, types, and requirements
extract_fields_from_json_schema <- function(schema_json_list) {
  # Navigate JSON structure to get record properties
  if (!("properties" %in% names(schema_json_list) &&
        "records" %in% names(schema_json_list$properties))) {
    stop("Schema must contain 'properties.records'")
  }

  records_schema <- schema_json_list$properties$records
  if (!("items" %in% names(records_schema) &&
        "properties" %in% names(records_schema$items))) {
    stop("Schema must contain 'properties.records.items.properties'")
  }

  record_props <- records_schema$items$properties
  required_fields <- rlang::`%||%`(records_schema$items$required, character())

  # Extract field information
  fields <- list()
  for (field_name in names(record_props)) {
    field_spec <- record_props[[field_name]]

    # Handle type - may be string or array (e.g., ["string", "null"])
    field_type <- field_spec$type
    if (is.null(field_type)) {
      field_type <- "string"
    } else if (length(field_type) > 1) {
      # For nullable types like ["string", "null"], take first non-null type
      field_type <- setdiff(field_type, "null")[1]
    }

    # Map JSON schema types to SQL types
    sql_type <- switch(field_type,
      "string" = "TEXT",
      "integer" = "INTEGER",
      "number" = "REAL",
      "boolean" = "BOOLEAN",
      "array" = "TEXT",  # Store as JSON
      "object" = "TEXT", # Store as JSON
      "TEXT" # Default fallback
    )

    fields[[field_name]] <- list(
      sql_type = sql_type,
      required = field_name %in% required_fields,
      description = rlang::`%||%`(field_spec$description, "")
    )
  }

  return(fields)
}

#' Validate schema compatibility with database (internal)
#' @param db_conn Database connection
#' @param schema_json_list Parsed JSON schema as list
#' @param table_name Database table name to validate against
#' @return List with validation results
#' @keywords internal
validate_schema_with_db <- function(db_conn, schema_json_list, table_name = "records") {
  # Extract schema fields
  schema_fields <- extract_fields_from_json_schema(schema_json_list)
  
  # Get database table structure
  tryCatch({
    db_info <- DBI::dbGetQuery(db_conn, paste0("PRAGMA table_info(", table_name, ")"))
    db_columns <- stats::setNames(db_info$type, db_info$name)
  }, error = function(e) {
    return(list(
      valid = FALSE,
      errors = paste("Failed to read database table structure:", e$message),
      warnings = character(0)
    ))
  })
  
  errors <- character(0)
  warnings <- character(0)
  
  # Check if schema fields can be stored in database
  for (field_name in names(schema_fields)) {
    if (!field_name %in% names(db_columns)) {
      if (schema_fields[[field_name]]$required) {
        errors <- c(errors, paste("Required field", field_name, "missing from database table"))
      } else {
        warnings <- c(warnings, paste("Optional field", field_name, "missing from database table"))
      }
    } else {
      # Check type compatibility (basic check)
      db_type <- db_columns[[field_name]]
      schema_type <- schema_fields[[field_name]]$sql_type
      
      # Basic type compatibility check
      compatible <- switch(paste(schema_type, db_type, sep = "->"),
        "TEXT->TEXT" = TRUE,
        "TEXT->VARCHAR" = TRUE,
        "INTEGER->INTEGER" = TRUE,
        "REAL->REAL" = TRUE,
        "REAL->NUMERIC" = TRUE,
        "BOOLEAN->BOOLEAN" = TRUE,
        "BOOLEAN->INTEGER" = TRUE, # SQLite stores booleans as integers
        FALSE # Default to incompatible
      )
      
      if (!compatible) {
        warnings <- c(warnings, paste("Type mismatch for", field_name, "- schema:", schema_type, "db:", db_type))
      }
    }
  }
  
  return(list(
    valid = length(errors) == 0,
    errors = errors,
    warnings = warnings,
    schema_fields = schema_fields,
    db_columns = db_columns
  ))
}

#' Generate SQL column definitions from JSON schema
#' @param schema_json_list Parsed JSON schema as list
#' @return Character string with SQL column definitions
generate_columns_from_json_schema <- function(schema_json_list) {
  schema_fields <- extract_fields_from_json_schema(schema_json_list)

  columns <- character(0)
  for (field_name in names(schema_fields)) {
    field_info <- schema_fields[[field_name]]
    null_constraint <- if (field_info$required) " NOT NULL" else ""

    columns <- c(columns, paste0("    ", field_name, " ", field_info$sql_type, null_constraint))
  }

  return(paste(columns, collapse = ",\n"))
}

#' Get document content (OCR results) from database (internal)
#' @param document_id Document ID to retrieve
#' @param db_conn Database connection
#' @return Character string with OCR markdown content, or NA if not found
#' @keywords internal
get_document_content <- function(document_id, db_conn) {
  tryCatch({
    result <- DBI::dbGetQuery(db_conn, "
      SELECT document_content FROM documents WHERE document_id = ?
    ", params = list(document_id))
    
    if (nrow(result) == 0 || is.null(result$document_content) || result$document_content == "") {
      return(NA)
    }
    
    return(result$document_content[1])
  }, error = function(e) {
    message("Error retrieving document content: ", e$message)
    return(NA)
  })
}

#' Get existing records from database (internal)
#' @param document_id Document ID to retrieve records for
#' @param db_conn Database connection
#' @return Dataframe with existing records, or NA if none found
#' @keywords internal
get_existing_records <- function(document_id, db_conn) {
  tryCatch({
    result <- DBI::dbGetQuery(db_conn, "
      SELECT * FROM records WHERE document_id = ?
    ", params = list(document_id)) |> tibble::as_tibble()
    return(result)
  }, error = function(e) {
    message("Error retrieving existing records: ", e$message)
    return(NA)
  })
}

#' Save reasoning to database (internal)
#' @param document_id Document ID
#' @param db_conn Database connection
#' @param reasoning_text Reasoning text to save
#' @param step Either "extraction" or "refinement"
#' @return NULL
#' @keywords internal
save_reasoning_to_db <- function(document_id, db_conn, reasoning_text, step = c("extraction", "refinement")) {
  step <- match.arg(step)
  column_name <- paste0(step, "_reasoning")

  sql <- paste0("UPDATE documents SET ", column_name, " = ? WHERE document_id = ?")

  DBI::dbExecute(db_conn, sql, params = list(reasoning_text, document_id))

  invisible(NULL)
}

