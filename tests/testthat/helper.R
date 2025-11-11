# Helper Functions for Tests
#
# Generic test helpers that don't assume specific schemas or domains

# Test Fixtures ----------------------------------------------------------------

#' Create a temporary test database with automatic cleanup
#'
#' Uses withr::local_tempfile() to ensure cleanup happens automatically
#' @param env Environment for cleanup (default: parent.frame())
#' @return Path to temporary SQLite database
local_test_db <- function(env = parent.frame()) {
  db_path <- withr::local_tempfile(fileext = ".sqlite", .local_envir = env)
  init_ecoextract_database(db_path)
  return(db_path)
}

#' Get database schema dynamically from JSON
#' @return Character vector of column names from the active schema
get_db_schema_columns <- function() {
  # Load schema using same priority order as init_ecoextract_database
  schema_path <- load_config_file(NULL, "schema.json", "extdata", return_content = FALSE)
  schema_json <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
  schema_json_list <- jsonlite::fromJSON(schema_json, simplifyVector = FALSE)

  # Extract field names from schema
  if (!is.null(schema_json_list$properties$records$items$properties)) {
    return(names(schema_json_list$properties$records$items$properties))
  }

  # Fallback to hard-coded if schema parsing fails
  return(c(
    "bat_species_scientific_name", "bat_species_common_name",
    "interacting_organism_scientific_name", "interacting_organism_common_name",
    "interaction_type", "location", "interaction_start_date", "interaction_end_date",
    "all_supporting_source_sentences", "page_number", "publication_year"
  ))
}

#' Create sample dataframe matching current schema
#' @return Dataframe with all schema columns populated with test data
sample_records <- function() {
  columns <- get_db_schema_columns()

  # Create a dataframe with 2 rows
  df <- data.frame(matrix(ncol = length(columns), nrow = 2))
  names(df) <- columns

  # Fill with appropriate test data based on column names
  for (col in columns) {
    if (grepl("_id$", col)) {
      df[[col]] <- c(1L, 2L)
    } else if (grepl("date", col, ignore.case = TRUE)) {
      df[[col]] <- c("2020-01-01", "2020-06-15")
    } else if (grepl("year", col, ignore.case = TRUE)) {
      df[[col]] <- c(2020L, 2021L)
    } else if (grepl("page", col, ignore.case = TRUE)) {
      df[[col]] <- c(5L, 12L)
    } else if (grepl("sentence|json|array", col, ignore.case = TRUE)) {
      df[[col]] <- c("[\"Test sentence 1\"]", "[\"Test sentence 2\"]")
    } else {
      # Generic string data
      df[[col]] <- c(paste("test", col, "1"), paste("test", col, "2"))
    }
  }

  return(df)
}

#' Create minimal valid dataframe (required columns only)
#' @return Dataframe with minimal required fields
minimal_records <- function() {
  # Get just the first row of sample data
  df <- sample_records()[1, , drop = FALSE]
  rownames(df) <- NULL
  return(df)
}

#' Get test document path
#' @return Path to test markdown document
get_test_document_path <- function() {
  system.file("extdata", "test_paper.md", package = "ecoextract")
}

#' Load sample OCR content from test document
#' @return Character string with test OCR content
sample_ocr_content <- function() {
  test_doc <- get_test_document_path()
  if (file.exists(test_doc)) {
    return(readLines(test_doc, warn = FALSE) |> paste(collapse = "\n"))
  }

  # Fallback if file not found
  "# Research Document

## Introduction

This is a test document with some content.

## Results

Table 1: Test data

| Column 1 | Column 2 |
|----------|----------|
| Value A  | Value B  |

## References

Author et al. (2020). Test Journal.
"
}

