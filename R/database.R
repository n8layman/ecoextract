#' Database Functions for EcoExtract Package
#' 
#' Standalone database operations for ecological interaction storage

#' Initialize EcoExtract database
#' @param db_path Path to SQLite database file
#' @return NULL (creates database with required tables)
#' @export
init_ecoextract_database <- function(db_path = "ecoextract_results.sqlite") {
  if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("RSQLite", quietly = TRUE)) {
    stop("DBI and RSQLite packages required for database operations")
  }
  
  # Create database directory if needed
  db_dir <- dirname(db_path)
  if (!dir.exists(db_dir) && db_dir != ".") {
    dir.create(db_dir, recursive = TRUE)
  }
  
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  
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
        
        -- Processing status
        ocr_status TEXT DEFAULT 'pending',
        extraction_status TEXT DEFAULT 'pending',
        refinement_status TEXT DEFAULT 'pending',
        
        -- Content storage
        document_content TEXT,  -- OCR markdown results
        ocr_audit TEXT         -- OCR quality audit (JSON)
      )
    ")
    
    # Create interactions table with dynamic schema based on ellmer
    schema_columns <- get_interaction_columns_sql()
    interaction_table_sql <- paste0("
      CREATE TABLE IF NOT EXISTS interactions (
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
        
        UNIQUE(document_id, occurrence_id),
        FOREIGN KEY (document_id) REFERENCES documents (id)
      )
    ")
    DBI::dbExecute(con, interaction_table_sql)
    
    # Create processing_log table for audit trail
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS processing_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        process_type TEXT NOT NULL,  -- 'ocr', 'extraction', 'refinement'
        status TEXT NOT NULL,        -- 'started', 'completed', 'failed'
        details TEXT,                -- JSON details or error message
        timestamp TEXT NOT NULL,
        FOREIGN KEY (document_id) REFERENCES documents (id)
      )
    ")
    
    # Create indexes for performance
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_documents_hash ON documents (file_hash)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_interactions_document ON interactions (document_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_interactions_occurrence ON interactions (occurrence_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_processing_log_document ON processing_log (document_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_processing_log_type ON processing_log (process_type)")
    
    cat("EcoExtract database initialized:", db_path, "\n")
    
  }, error = function(e) {
    cat("Error initializing EcoExtract database:", e$message, "\n")
    stop(e)
  }, finally = {
    DBI::dbDisconnect(con)
  })
}

#' Get interaction table column definitions as SQL
#' @param ellmer_schema Optional ellmer schema object to generate columns from
#' @return Character string with column definitions
get_interaction_columns_sql <- function(ellmer_schema = NULL) {
  if (!is.null(ellmer_schema)) {
    # Generate columns dynamically from ellmer schema
    return(paste0(generate_columns_from_ellmer_schema(ellmer_schema), ","))
  }
  
  # Fallback to basic schema if no ellmer schema provided
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

#' Save document to EcoExtract database
#' @param db_path Path to database file
#' @param file_path Path to processed file
#' @param file_hash Optional file hash (computed automatically if not provided)
#' @param metadata List with document metadata
#' @return Document ID or NULL if failed
#' @export
save_document_to_db <- function(db_path, file_path, file_hash = NULL, metadata = list()) {
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)

  tryCatch({
    # Compute file hash if not provided
    if (is.null(file_hash)) {
      if (file.exists(file_path)) {
        file_hash <- digest::digest(file_path, file = TRUE, algo = "md5")
      } else {
        # For test cases where file doesn't exist, use path as hash
        file_hash <- digest::digest(file_path, algo = "md5")
      }
    }

    # Check if document already exists
    existing <- DBI::dbGetQuery(con, "
      SELECT id FROM documents WHERE file_hash = ?
    ", params = list(file_hash))
    
    if (nrow(existing) > 0) {
      return(existing$id[1])  # Return existing document ID
    }
    
    # Insert new document
    DBI::dbExecute(con, "
      INSERT INTO documents (
        file_name, file_path, file_hash, file_size, upload_timestamp,
        title, first_author_lastname, publication_year, doi
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      basename(file_path),
      file_path,
      file_hash,
      as.numeric(file.info(file_path)$size),
      as.character(Sys.time()),
      metadata$title %||% NA_character_,
      metadata$first_author_lastname %||% NA_character_,
      metadata$publication_year %||% NA_integer_,
      metadata$doi %||% NA_character_
    ))
    
    # Get the new document ID
    new_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id
    return(new_id)
    
  }, error = function(e) {
    cat("Error saving document to database:", e$message, "\n")
    return(NULL)
  }, finally = {
    DBI::dbDisconnect(con)
  })
}

#' Save interactions to EcoExtract database
#' @param db_path Path to database file
#' @param document_id Document ID
#' @param interactions_df Dataframe of interactions
#' @param metadata Processing metadata
#' @return TRUE if successful
#' @export
save_records_to_db <- function(db_path, document_id, interactions_df, metadata = list()) {
  if (nrow(interactions_df) == 0) return(TRUE)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)

  tryCatch({
    # Add occurrence IDs if not present
    if (!"occurrence_id" %in% names(interactions_df)) {
      # Try to get author/year from publication_metadata in metadata or from interactions themselves
      author_lastname <- metadata$publication_metadata$first_author_lastname %||%
        interactions_df$first_author_lastname[1] %||%
        "Unknown"
      publication_year <- metadata$publication_metadata$publication_year %||%
        interactions_df$publication_year[1] %||%
        format(Sys.Date(), "%Y")

      interactions_df <- add_occurrence_ids(interactions_df, author_lastname, publication_year)
    }

    # Add required metadata columns
    interactions_df$document_id <- as.integer(document_id)
    interactions_df$extraction_timestamp <- as.character(Sys.time())
    interactions_df$llm_model_version <- metadata$model %||% "unknown"
    interactions_df$prompt_hash <- metadata$prompt_hash %||% "unknown"
    
    # Ensure all_supporting_source_sentences is JSON
    if ("all_supporting_source_sentences" %in% names(interactions_df)) {
      interactions_df$all_supporting_source_sentences <- vapply(
        interactions_df$all_supporting_source_sentences,
        function(x) {
          if (is.list(x) || is.character(x) && length(x) > 1) {
            jsonlite::toJSON(x, auto_unbox = FALSE)
          } else {
            as.character(x)
          }
        },
        FUN.VALUE = character(1)
      )
    }
    
    # Get database column names dynamically
    db_columns <- DBI::dbListFields(con, "interactions")

    # Add missing columns with NA values (must be same length as dataframe)
    num_rows <- nrow(interactions_df)
    for (col in db_columns) {
      if (!col %in% names(interactions_df)) {
        interactions_df[[col]] <- rep(NA, num_rows)
      }
    }

    # Filter to only include columns that exist in database (in correct order)
    interactions_clean <- interactions_df |>
      dplyr::select(dplyr::all_of(db_columns))

    # Convert any list columns to character (JSON or string)
    for (col in names(interactions_clean)) {
      if (is.list(interactions_clean[[col]])) {
        interactions_clean[[col]] <- vapply(interactions_clean[[col]],
                                             function(x) if(is.null(x)) NA_character_ else as.character(x),
                                             FUN.VALUE = character(1))
      }
    }

    # Convert types to match database schema
    # SQLite stores BOOLEAN as INTEGER (0/1), so convert logical to integer
    if ("flagged_for_review" %in% names(interactions_clean)) {
      interactions_clean$flagged_for_review <- vapply(interactions_clean$flagged_for_review,
        function(x) {
          if (is.logical(x)) return(as.integer(x))
          if (is.character(x)) return(as.integer(tolower(x) %in% c("true", "t", "1", "yes")))
          return(as.integer(as.logical(x)))
        }, FUN.VALUE = integer(1))
    }
    if ("organisms_identifiable" %in% names(interactions_clean)) {
      interactions_clean$organisms_identifiable <- vapply(interactions_clean$organisms_identifiable,
        function(x) {
          if (is.logical(x)) return(as.integer(x))
          if (is.character(x)) return(as.integer(tolower(x) %in% c("true", "t", "1", "yes")))
          return(as.integer(as.logical(x)))
        }, FUN.VALUE = integer(1))
    }
    if ("page_number" %in% names(interactions_clean)) {
      interactions_clean$page_number <- as.integer(interactions_clean$page_number)
    }
    if ("publication_year" %in% names(interactions_clean)) {
      interactions_clean$publication_year <- as.integer(interactions_clean$publication_year)
    }

    # Insert interactions
    DBI::dbWriteTable(con, "interactions", interactions_clean, append = TRUE, row.names = FALSE)
    
    cat("Saved", nrow(interactions_clean), "interactions to database\n")
    return(TRUE)
    
  }, error = function(e) {
    cat("Error saving interactions to database:", e$message, "\n")
    return(FALSE)
  }, finally = {
    DBI::dbDisconnect(con)
  })
}

#' Get database statistics
#' @param db_path Path to database file
#' @return List with database statistics
#' @export
get_db_stats <- function(db_path) {
  if (!file.exists(db_path)) {
    return(list(documents = 0, interactions = 0, message = "Database not found"))
  }
  
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  
  tryCatch({
    doc_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM documents")$n
    int_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM interactions")$n
    
    return(list(
      documents = doc_count,
      interactions = int_count,
      message = paste("Database contains", doc_count, "documents and", int_count, "interactions")
    ))
    
  }, error = function(e) {
    return(list(documents = 0, interactions = 0, message = paste("Database error:", e$message)))
  }, finally = {
    DBI::dbDisconnect(con)
  })
}

#' Log processing step
#' @param db_path Path to database file  
#' @param document_id Document ID
#' @param process_type Type of process ('ocr', 'extraction', 'refinement')
#' @param status Status ('started', 'completed', 'failed')
#' @param details Additional details or error message
log_processing_step <- function(db_path, document_id, process_type, status, details = NULL) {
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  
  tryCatch({
    DBI::dbExecute(con, "
      INSERT INTO processing_log (document_id, process_type, status, details, timestamp)
      VALUES (?, ?, ?, ?, ?)
    ", params = list(document_id, process_type, status, details %||% "", Sys.time()))
  }, error = function(e) {
    cat("Error logging processing step:", e$message, "\n")
  }, finally = {
    DBI::dbDisconnect(con)
  })
}

#' Extract field definitions from ellmer schema
#' @param ellmer_schema ellmer schema object (type_object)
#' @return Named list with field names, types, and requirements
extract_ellmer_schema_fields <- function(ellmer_schema) {
  if (!inherits(ellmer_schema, "TypeObject")) {
    stop("Schema must be an ellmer TypeObject")
  }
  
  # Get the interactions type from the schema
  interactions_type <- NULL
  if ("interactions" %in% names(ellmer_schema$properties)) {
    # Extract the items type from the array
    interactions_array <- ellmer_schema$properties$interactions
    if (inherits(interactions_array, "TypeArray")) {
      interactions_type <- interactions_array$items
    }
  }
  
  if (is.null(interactions_type) || !inherits(interactions_type, "TypeObject")) {
    stop("Schema must contain 'interactions' array with TypeObject items")
  }
  
  # Extract field information
  fields <- list()
  for (field_name in names(interactions_type$properties)) {
    field_obj <- interactions_type$properties[[field_name]]
    
    # Map ellmer types to SQL types
    sql_type <- switch(class(field_obj)[1],
      "TypeString" = "TEXT",
      "TypeInteger" = "INTEGER", 
      "TypeNumber" = "REAL",
      "TypeBoolean" = "BOOLEAN",
      "TypeArray" = "TEXT", # Store as JSON
      "TypeObject" = "TEXT", # Store as JSON
      "TEXT" # Default fallback
    )
    
    fields[[field_name]] <- list(
      sql_type = sql_type,
      required = field_obj$required %||% TRUE,
      description = field_obj$description %||% ""
    )
  }
  
  return(fields)
}

#' Validate ellmer schema compatibility with database
#' @param db_conn Database connection
#' @param ellmer_schema ellmer schema object 
#' @param table_name Database table name to validate against
#' @return List with validation results
#' @export
validate_ellmer_schema_with_db <- function(db_conn, ellmer_schema, table_name = "interactions") {
  # Extract schema fields
  schema_fields <- extract_ellmer_schema_fields(ellmer_schema)
  
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

#' Generate SQL column definitions from ellmer schema
#' @param ellmer_schema ellmer schema object
#' @return Character string with SQL column definitions
generate_columns_from_ellmer_schema <- function(ellmer_schema) {
  schema_fields <- extract_ellmer_schema_fields(ellmer_schema)
  
  columns <- character(0)
  for (field_name in names(schema_fields)) {
    field_info <- schema_fields[[field_name]]
    null_constraint <- if (field_info$required) " NOT NULL" else ""
    
    columns <- c(columns, paste0("    ", field_name, " ", field_info$sql_type, null_constraint))
  }
  
  return(paste(columns, collapse = ",\n"))
}

#' Get document content (OCR results) from database
#' @param document_id Document ID to retrieve
#' @param db_conn Database connection
#' @return Character string with OCR markdown content, or NA if not found
#' @export
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
    cat("Error retrieving document content:", e$message, "\n")
    return(NA)
  })
}

#' Get OCR audit data from database
#' @param document_id Document ID to retrieve
#' @param db_conn Database connection
#' @return OCR audit data (JSON string), or NA if not found
#' @export
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
    cat("Error retrieving OCR audit:", e$message, "\n")
    return(NA)
  })
}

#' Get existing interactions from database
#' @param document_id Document ID to retrieve interactions for
#' @param db_conn Database connection
#' @return Dataframe with existing interactions, or NA if none found
#' @export
get_existing_interactions <- function(document_id, db_conn) {
  tryCatch({
    result <- DBI::dbGetQuery(db_conn, "
      SELECT * FROM interactions WHERE document_id = ?
    ", params = list(document_id))
    
    if (nrow(result) == 0) {
      return(NA)
    }
    
    return(result)
  }, error = function(e) {
    cat("Error retrieving existing interactions:", e$message, "\n")
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