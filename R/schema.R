#' Schema Validation Functions
#' 
#' Dynamic validation using ellmer schema for ecological interactions

#' Validate interactions data against ellmer schema
#' @param interactions_df Dataframe to validate
#' @param strict If TRUE, requires all fields to be present
#' @return List with validation results
#' @export
validate_interactions_schema <- function(interactions_df, strict = FALSE) {
  if (!is.data.frame(interactions_df) || nrow(interactions_df) == 0) {
    return(list(
      valid = FALSE,
      errors = "No data provided or empty dataframe",
      warnings = character(0)
    ))
  }
  
  errors <- character(0)
  warnings <- character(0)
  
  # Get expected columns from basic schema (fallback without ellmer dependency)
  expected_columns <- c(
    "bat_species_scientific_name", "bat_species_common_name",
    "interacting_organism_scientific_name", "interacting_organism_common_name", 
    "interaction_type", "location", "interaction_start_date", "interaction_end_date",
    "all_supporting_source_sentences", "page_number", "publication_year"
  )
  current_columns <- names(interactions_df)
  
  # Check for missing required columns
  if (strict) {
    required_columns <- c("bat_species_scientific_name", "bat_species_common_name")
    missing_columns <- setdiff(required_columns, current_columns)
    if (length(missing_columns) > 0) {
      errors <- c(errors, paste("Missing required columns:", paste(missing_columns, collapse = ", ")))
    }
  }
  
  # Check for unexpected columns
  unexpected_columns <- setdiff(current_columns, expected_columns)
  if (length(unexpected_columns) > 0) {
    warnings <- c(warnings, paste("Unexpected columns (will be ignored):", paste(unexpected_columns, collapse = ", ")))
  }
  
  # Basic data type validation (without ellmer dependency)
  for (col in intersect(current_columns, expected_columns)) {
    actual_class <- class(interactions_df[[col]])[1]
    
    # Basic type checking - most fields should be character
    if (col %in% c("page_number", "publication_year") && !is.numeric(interactions_df[[col]]) && !is.integer(interactions_df[[col]])) {
      warnings <- c(warnings, paste("Column", col, "should be numeric but is", actual_class))
    }
  }
  
  # Check for required data (non-empty values in key fields)
  key_fields <- c("bat_species_scientific_name", "bat_species_common_name")
  for (field in key_fields) {
    if (field %in% current_columns) {
      empty_count <- sum(is.na(interactions_df[[field]]) | interactions_df[[field]] == "")
      if (empty_count > 0) {
        warnings <- c(warnings, paste(empty_count, "rows have empty", field))
      }
    }
  }
  
  return(list(
    valid = length(errors) == 0,
    errors = errors,
    warnings = warnings
  ))
}

#' Get column names from basic schema (internal)
#' @return Character vector of column names
#' @keywords internal
get_schema_columns <- function() {
  c(
    "bat_species_scientific_name", "bat_species_common_name",
    "interacting_organism_scientific_name", "interacting_organism_common_name", 
    "interaction_type", "location", "interaction_start_date", "interaction_end_date",
    "all_supporting_source_sentences", "page_number", "publication_year"
  )
}

#' Get database column types from basic schema (internal)
#' @return Named vector of SQL types
#' @keywords internal
get_schema_types <- function() {
  types <- c(
    "bat_species_scientific_name" = "TEXT",
    "bat_species_common_name" = "TEXT",
    "interacting_organism_scientific_name" = "TEXT", 
    "interacting_organism_common_name" = "TEXT",
    "interaction_type" = "TEXT",
    "location" = "TEXT",
    "interaction_start_date" = "TEXT",
    "interaction_end_date" = "TEXT", 
    "all_supporting_source_sentences" = "TEXT",
    "page_number" = "INTEGER",
    "publication_year" = "INTEGER"
  )
  return(types)
}

#' Get required columns from basic schema (internal)
#' @return Character vector of required column names
#' @keywords internal
get_required_columns <- function() {
  # Default required columns
  c("bat_species_scientific_name", "bat_species_common_name")
}

#' Filter dataframe to include only schema-defined columns (internal)
#' @param df Dataframe to filter
#' @return Dataframe with only known schema columns
#' @keywords internal
filter_to_schema_columns <- function(df) {
  schema_cols <- get_schema_columns()
  df |>
    dplyr::select(dplyr::any_of(schema_cols))
}

#' Add missing schema columns with appropriate defaults (internal)
#' @param df Dataframe to enhance
#' @return Dataframe with all schema columns
#' @keywords internal
add_missing_schema_columns <- function(df) {
  schema_cols <- get_schema_columns()
  schema_types <- get_schema_types()
  missing_cols <- setdiff(schema_cols, names(df))

  for (col in missing_cols) {
    col_type <- schema_types[[col]]
    # Add column with appropriate default based on type
    if (col_type == "TEXT") {
      df[[col]] <- NA_character_
    } else if (col_type == "INTEGER") {
      df[[col]] <- NA_integer_
    } else {
      df[[col]] <- NA_character_  # Default to character
    }
  }

  return(df)
}

#' Validate and prepare dataframe for database operations (internal)
#' @param df Dataframe to validate and prepare
#' @return Clean dataframe ready for database operations
#' @keywords internal
validate_and_prepare_for_db <- function(df) {
  # First validate
  validation_result <- validate_interactions_schema(df, strict = FALSE)

  if (!validation_result$valid) {
    warning("Schema validation failed: ", paste(validation_result$errors, collapse = "; "))
  }

  if (length(validation_result$warnings) > 0) {
    message("Schema warnings: ", paste(validation_result$warnings, collapse = "; "))
  }

  # Filter to known columns and add missing ones
  clean_df <- df |>
    filter_to_schema_columns() |>
    add_missing_schema_columns()

  return(clean_df)
}

#' Get comprehensive schema information (internal)
#' @return List with schema details
#' @keywords internal
get_database_schema <- function() {
  list(
    columns = get_schema_columns(),
    types = get_schema_types(),
    required = get_required_columns()
  )
}