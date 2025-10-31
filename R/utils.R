#' Internal utility functions

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
