#' Internal utility functions

#' Load environment variables from .env files
#'
#' Loads environment variables from any file starting with `.env`. This allows
#' user-specific options to be set in `.env_user` (which is .gitignored), and
#' to have both encrypted and non-encrypted .env files.
#'
#' @return NULL (invisibly). Called for side effects.
#' @export
load_env <- function() {
  for (env_file in list.files(all.files = TRUE, pattern = "^\\.env.*")) {
    try(readRenviron(env_file), silent = TRUE)
  }
  invisible(NULL)
}

#' Create occurrence IDs for a batch of records (internal)
#' @param interactions Dataframe of records
#' @param author_lastname Author lastname for ID generation
#' @param publication_year Publication year for ID generation
#' @return Dataframe with occurrence_id column added
#' @keywords internal
add_occurrence_ids <- function(interactions, author_lastname, publication_year) {
  if (nrow(interactions) == 0) {
    return(interactions)
  }

  # Generate sequential occurrence IDs
  interactions$occurrence_id <- sapply(1:nrow(interactions), function(i) {
    generate_occurrence_id(author_lastname, publication_year, i)
  })

  return(interactions)
}

#' Simple logging function
#' @param message Message to log
#' @param level Log level (INFO, WARNING, ERROR)
log_message <- function(message, level = "INFO") {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat("[", timestamp, "] ", level, ": ", message, "\n", sep = "")
}

estimate_tokens <- function(text) {
  # Handle NULL input
  if (is.null(text)) {
    return(0)
  }

  # Convert to JSON if not already a character
  if (!is.character(text)) {
    tryCatch({
      text <- jsonlite::toJSON(text, auto_unbox = TRUE)
    }, error = function(e) {
      # If JSON conversion fails, try deparse then as.character as fallback
      tryCatch({
        text <- paste(deparse(text), collapse = " ")
      }, error = function(e2) {
        # Ultimate fallback for unconvertible objects
        text <- "unknown"
      })
    })
  }

  # Handle NA or empty string after conversion
  if (length(text) == 0 || is.na(text) || text == "") {
    return(0)
  }

  ceiling(nchar(text) / 4)
}

#' Build existing records context for LLM prompts
#' @param existing_records Dataframe of existing records
#' @param document_id Optional document ID for context
#' @return Character string with existing records formatted for LLM context
#' @keywords internal
build_existing_records_context <- function(existing_records, document_id = NULL) {
  if (is.null(existing_records) || !is.data.frame(existing_records) || nrow(existing_records) == 0) {
    return("")  # Return empty string, context header handles the messaging
  }

  # Filter out deleted records - they should not be shown to extraction/refinement
  if ("deleted_by_user" %in% names(existing_records)) {
    existing_records <- existing_records[is.na(existing_records$deleted_by_user) | !existing_records$deleted_by_user, ]
  }

  # Recheck if any records remain after filtering
  if (nrow(existing_records) == 0) {
    return("")  # Return empty string
  }

  # Exclude metadata columns AND occurrence_id from display
  # We don't show occurrence_id to LLM - we'll match records by content instead
  metadata_cols <- c("id", "occurrence_id", "document_id", "extraction_timestamp",
                     "llm_model_version", "prompt_hash", "flagged_for_review",
                     "review_reason", "human_edited", "rejected", "deleted_by_user")
  data_cols <- setdiff(names(existing_records), metadata_cols)

  # Build context as simple JSON representation
  context_lines <- c("Existing records:", "")

  for (i in seq_len(nrow(existing_records))) {
    row <- existing_records[i, data_cols, drop = FALSE]

    # Convert row to simple key-value format
    record_parts <- character(0)
    for (col in data_cols) {
      val <- row[[col]]

      # Convert lists to JSON strings
      if (is.list(val)) {
        val <- jsonlite::toJSON(val, auto_unbox = TRUE)
      }

      # Include value if it's not NA and not empty
      # Need to check for length > 0 first to avoid issues with lists/vectors
      if (length(val) > 0 && !all(is.na(val))) {
        val_str <- as.character(val)
        if (nchar(val_str) > 0 && val_str != "") {
          # Truncate very long values (like supporting_source_sentences)
          if (nchar(val_str) > 100) {
            val_str <- paste0(substr(val_str, 1, 97), "...")
          }
          record_parts <- c(record_parts, paste0(col, ": ", val_str))
        }
      }
    }

    context_line <- paste0("- ", paste(record_parts, collapse = ", "))
    context_lines <- c(context_lines, context_line)
  }

  return(paste(context_lines, collapse = "\n"))
}
