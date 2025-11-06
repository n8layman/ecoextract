#' Database Functions for EcoExtract Package
#' 
#' Standalone database operations for ecological interaction storage

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
    close_on_exit <- TRUE
  }

  tryCatch({
    # Create documents table
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_hash TEXT UNIQUE NOT NULL,
        file_size INTEGER,
        upload_timestamp TEXT NOT NULL,

        -- Publication metadata
        title TEXT,
        first_author_lastname TEXT,
        publication_year INTEGER,
        doi TEXT,
        journal TEXT,

        -- Content storage
        document_content TEXT,  -- OCR markdown results
        ocr_audit TEXT,         -- OCR quality audit (JSON)
        ocr_images TEXT         -- OCR images (JSON array of base64 images)
      )
    ")

    # Load schema if provided
    schema_json_list <- NULL
    if (!is.null(schema_file)) {
      schema_path <- load_config_file(schema_file, "schema.json", "extdata", return_content = FALSE)
      schema_json <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
      schema_json_list <- jsonlite::fromJSON(schema_json, simplifyVector = FALSE)
    }

    # Create records table with dynamic schema
    schema_columns <- get_record_columns_sql(schema_json_list)
    record_table_sql <- paste0("
      CREATE TABLE IF NOT EXISTS records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        occurrence_id TEXT NOT NULL,
        ", schema_columns, "

        -- Processing metadata
        extraction_timestamp TEXT NOT NULL,
        llm_model_version TEXT NOT NULL,
        prompt_hash TEXT NOT NULL,
        flagged_for_review BOOLEAN DEFAULT FALSE,
        review_reason TEXT,
        human_edited BOOLEAN DEFAULT FALSE,
        rejected BOOLEAN DEFAULT FALSE,
        deleted_by_user BOOLEAN DEFAULT FALSE,

        UNIQUE(document_id, occurrence_id),
        FOREIGN KEY (document_id) REFERENCES documents (id)
      )
    ")
    DBI::dbExecute(con, record_table_sql)

    # Create indexes for performance
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_documents_hash ON documents (file_hash)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_records_document ON records (document_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_records_occurrence ON records (occurrence_id)")

    # Migration: Add deleted_by_user column if it doesn't exist
    tryCatch({
      # Check if column exists by trying to query it
      DBI::dbGetQuery(con, "SELECT deleted_by_user FROM records LIMIT 0")
    }, error = function(e) {
      # Column doesn't exist, add it
      cat("Migrating database: Adding deleted_by_user column\n")
      DBI::dbExecute(con, "ALTER TABLE records ADD COLUMN deleted_by_user BOOLEAN DEFAULT FALSE")
    })

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
#' @param schema_json_list Optional parsed JSON schema to generate columns from
#' @return Character string with column definitions
get_record_columns_sql <- function(schema_json_list = NULL) {
  if (!is.null(schema_json_list)) {
    # Generate columns dynamically from JSON schema
    return(paste0(generate_columns_from_json_schema(schema_json_list), ","))
  }

  # Fallback to basic schema if no schema provided
  "
    bat_species_scientific_name TEXT,
    bat_species_common_name TEXT,
    interacting_organism_scientific_name TEXT,
    interacting_organism_common_name TEXT,
    interaction_type TEXT,
    interaction_start_date TEXT,
    interaction_end_date TEXT,
    location TEXT,
    all_supporting_source_sentences TEXT,  -- JSON array
    page_number INTEGER,
    publication_year INTEGER,
  "
}

#' Save document to EcoExtract database (internal)
#' @param db_conn Database connection or path to database file
#' @param file_path Path to processed file
#' @param file_hash Optional file hash (computed automatically if not provided)
#' @param metadata List with document metadata
#' @return Document ID or NULL if failed
#' @keywords internal
save_document_to_db <- function(db_conn, file_path, file_hash = NULL, metadata = list()) {
  # Accept either a connection object or a path string
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

  # Compute file hash if not provided
  if (is.null(file_hash)) {
    if (file.exists(file_path)) {
      file_hash <- digest::digest(file_path, file = TRUE, algo = "md5")
    } else {
      # For test cases where file doesn't exist, use path as hash
      file_hash <- digest::digest(file_path, algo = "md5")
    }
  }

  # Check if document already exists (to preserve document ID)
  existing <- DBI::dbGetQuery(con, "
    SELECT id FROM documents WHERE file_hash = ?
  ", params = list(file_hash))

  doc_id <- if (nrow(existing) > 0) existing$id[1] else NULL

  # INSERT OR REPLACE - overwrites entire row if exists, inserts if new
  file_size <- if (file.exists(file_path)) {
    as.numeric(file.info(file_path)$size)
  } else {
    NA_integer_
  }

  if (is.null(doc_id)) {
    # New document - INSERT without specifying id (auto-generated)
    DBI::dbExecute(con, "
      INSERT INTO documents (
        file_name, file_path, file_hash, file_size, upload_timestamp,
        title, first_author_lastname, publication_year, doi, journal,
        document_content, ocr_audit, ocr_images
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      basename(file_path),
      file_path,
      file_hash,
      file_size,
      as.character(Sys.time()),
      metadata$title %||% NA_character_,
      metadata$first_author_lastname %||% NA_character_,
      metadata$publication_year %||% NA_integer_,
      metadata$doi %||% NA_character_,
      metadata$journal %||% NA_character_,
      metadata$document_content %||% NA_character_,
      metadata$ocr_audit %||% NA_character_,
      metadata$ocr_images %||% NA_character_
    ))

    # Get the new document ID
    return(DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id)

  } else {
    # Existing document - REPLACE with explicit id
    DBI::dbExecute(con, "
      INSERT OR REPLACE INTO documents (
        id, file_name, file_path, file_hash, file_size, upload_timestamp,
        title, first_author_lastname, publication_year, doi, journal,
        document_content, ocr_audit, ocr_images
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      doc_id,
      basename(file_path),
      file_path,
      file_hash,
      file_size,
      as.character(Sys.time()),
      metadata$title %||% NA_character_,
      metadata$first_author_lastname %||% NA_character_,
      metadata$publication_year %||% NA_integer_,
      metadata$doi %||% NA_character_,
      metadata$journal %||% NA_character_,
      metadata$document_content %||% NA_character_,
      metadata$ocr_audit %||% NA_character_,
      metadata$ocr_images %||% NA_character_
    ))

    # Return the existing document ID
    return(doc_id)
  }
}

#' Save publication metadata to existing document (internal)
#' @param document_id Document ID
#' @param db_conn Database connection
#' @param metadata List with metadata fields (title, first_author_lastname, publication_year, doi, journal, ocr_audit)
#' @return Document ID
#' @keywords internal
save_metadata_to_db <- function(document_id, db_conn, metadata = list()) {
  # Update documents table with metadata
  DBI::dbExecute(db_conn,
    "UPDATE documents
     SET title = ?,
         first_author_lastname = ?,
         publication_year = ?,
         doi = ?,
         journal = ?,
         ocr_audit = ?
     WHERE id = ?",
    params = list(
      metadata$title %||% NA_character_,
      metadata$first_author_lastname %||% NA_character_,
      metadata$publication_year %||% NA_integer_,
      metadata$doi %||% NA_character_,
      metadata$journal %||% NA_character_,
      metadata$ocr_audit %||% NA_character_,
      document_id
    )
  )

  return(document_id)
}

#' Save records to EcoExtract database (internal)
#' @param db_path Path to database file
#' @param document_id Document ID
#' @param interactions_df Dataframe of records
#' @param metadata Processing metadata
#' @return TRUE if successful
#' @keywords internal
save_records_to_db <- function(db_path, document_id, interactions_df, metadata = list()) {
  if (nrow(interactions_df) == 0) return(invisible(NULL))

  # Accept either a path (string) or a connection object
  if (inherits(db_path, "SQLiteConnection")) {
    con <- db_path
    close_on_exit <- FALSE
  } else {
    con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    close_on_exit <- TRUE
  }

  if (close_on_exit) {
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }

  # Handle occurrence IDs - mix of existing (valid) and new (null/invalid) records
  # Valid IDs: Match pattern "Author2023-o1" format (from refinement preserving existing records)
  # Invalid IDs: Don't match pattern, are NA, or are null (from extraction or refinement's new records)

  if ("occurrence_id" %in% names(interactions_df) && nrow(interactions_df) > 0) {
    # Check each ID for validity
    valid_pattern <- "^[A-Za-z]+[0-9]+-o[0-9]+$"
    is_valid <- !is.na(interactions_df$occurrence_id) &
                grepl(valid_pattern, interactions_df$occurrence_id)

    valid_count <- sum(is_valid)
    invalid_count <- sum(!is_valid)

    if (valid_count > 0 && invalid_count > 0) {
      message(glue::glue("Mixed IDs: {valid_count} existing (preserved), {invalid_count} new (generating)"))
    } else if (valid_count > 0) {
      message(glue::glue("Preserving existing occurrence IDs for {valid_count} records"))
    } else {
      message(glue::glue("Generating occurrence IDs for {invalid_count} new records"))
    }

    # Only generate IDs for records with invalid/missing IDs
    if (invalid_count > 0) {
      # Get publication metadata
      doc_meta <- DBI::dbGetQuery(con,
        "SELECT first_author_lastname, publication_year FROM documents WHERE id = ?",
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
        "SELECT occurrence_id FROM records WHERE document_id = ?",
        params = list(document_id))$occurrence_id

      max_seq <- 0
      if (length(existing_ids) > 0) {
        # Extract sequence numbers from existing IDs
        seqs <- as.integer(sub(".*-o([0-9]+)$", "\\1", existing_ids))
        max_seq <- max(seqs, na.rm = TRUE)
      }

      # Generate new IDs starting after max existing
      new_id_count <- 0
      for (i in which(!is_valid)) {
        new_id_count <- new_id_count + 1
        interactions_df$occurrence_id[i] <- paste0(author_lastname, publication_year, "-o", max_seq + new_id_count)
      }
    }
  } else {
    # No occurrence_id column or empty dataframe - generate all IDs
    doc_meta <- DBI::dbGetQuery(con,
      "SELECT first_author_lastname, publication_year FROM documents WHERE id = ?",
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

    interactions_df <- add_occurrence_ids(interactions_df, author_lastname, publication_year)
    message(glue::glue("Generated occurrence IDs for {nrow(interactions_df)} records"))
  }

  # Add required metadata columns
  interactions_df$document_id <- as.integer(document_id)
  interactions_df$extraction_timestamp <- as.character(Sys.time())
  interactions_df$llm_model_version <- metadata$model %||% "unknown"
  interactions_df$prompt_hash <- metadata$prompt_hash %||% "unknown"

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

  # Convert metadata fields we add (not schema-specific)
  # SQLite stores BOOLEAN as INTEGER (0/1), so convert logical to integer
  if ("flagged_for_review" %in% names(interactions_clean)) {
    col_data <- interactions_clean$flagged_for_review
    if (!is.null(col_data) && length(col_data) > 0 && is.logical(col_data)) {
      interactions_clean$flagged_for_review <- as.integer(col_data)
    }
  }
  if ("human_edited" %in% names(interactions_clean)) {
    col_data <- interactions_clean$human_edited
    if (!is.null(col_data) && length(col_data) > 0 && is.logical(col_data)) {
      interactions_clean$human_edited <- as.integer(col_data)
    }
  }
  if ("rejected" %in% names(interactions_clean)) {
    col_data <- interactions_clean$rejected
    if (!is.null(col_data) && length(col_data) > 0 && is.logical(col_data)) {
      interactions_clean$rejected <- as.integer(col_data)
    }
  }

  # ellmer handles schema-defined types (integers, strings, etc.) correctly
  # SQLite will auto-coerce types as needed when inserting

  # Use UPSERT logic: update existing records, insert new ones
  # This preserves data and handles both extraction (new records) and refinement (updates)

  for (i in 1:nrow(interactions_clean)) {
    row <- interactions_clean[i, ]

    # Check if this occurrence_id already exists for this document
    existing <- DBI::dbGetQuery(con,
      "SELECT id FROM records WHERE document_id = ? AND occurrence_id = ?",
      params = list(row$document_id, row$occurrence_id))

    if (nrow(existing) > 0) {
      # Update existing record (only if not human_edited and not rejected)
      # Build SET clause dynamically for all columns except id
      cols_to_update <- setdiff(names(row), c("id"))
      set_clause <- paste(paste0(cols_to_update, " = ?"), collapse = ", ")

      update_sql <- paste0(
        "UPDATE records SET ", set_clause,
        " WHERE id = ? AND human_edited = 0 AND rejected = 0"
      )

      params <- unname(c(as.list(row[cols_to_update]), list(existing$id[1])))
      DBI::dbExecute(con, update_sql, params = params)
    } else {
      # Insert new record
      DBI::dbWriteTable(con, "records", row, append = TRUE, row.names = FALSE)
    }
  }

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
  required_fields <- records_schema$items$required %||% character()

  # Extract field information
  fields <- list()
  for (field_name in names(record_props)) {
    field_spec <- record_props[[field_name]]

    # Map JSON schema types to SQL types
    sql_type <- switch(field_spec$type,
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
      description = field_spec$description %||% ""
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
      SELECT document_content FROM documents WHERE id = ?
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

#' Get OCR audit data from database (internal)
#' @param document_id Document ID to retrieve
#' @param db_conn Database connection
#' @return OCR audit data (JSON string), or NA if not found
#' @keywords internal
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

#' Simple null coalescing operator
#' @param x First value to check
#' @param y Default value to use if x is NULL or empty
#' @return Either x if not NULL/empty, or y
#' @keywords internal
#' @noRd
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (is.character(x) && x == "")) y else x
}
