test_that("validate_interactions_schema accepts valid data", {
  valid_data <- sample_interactions()
  result <- validate_interactions_schema(valid_data, strict = FALSE)

  expect_true(result$valid)
  expect_length(result$errors, 0)
})

test_that("validate_interactions_schema handles empty dataframe", {
  empty_df <- data.frame()
  result <- validate_interactions_schema(empty_df)

  expect_false(result$valid)
  expect_match(result$errors, "No data provided|empty dataframe")
})

test_that("validate_interactions_schema detects missing required columns in strict mode", {
  incomplete_data <- data.frame(
    bat_species_scientific_name = "Myotis lucifugus",
    stringsAsFactors = FALSE
  )
  result <- validate_interactions_schema(incomplete_data, strict = TRUE)

  expect_false(result$valid)
  expect_true(any(grepl("bat_species_common_name", result$errors)))
})

test_that("validate_interactions_schema warns about unexpected columns", {
  extra_cols_data <- sample_interactions()
  extra_cols_data$unexpected_field <- "test"

  result <- validate_interactions_schema(extra_cols_data, strict = FALSE)

  expect_true(any(grepl("Unexpected columns", result$warnings)))
  expect_true(any(grepl("unexpected_field", result$warnings)))
})

test_that("validate_interactions_schema warns about type mismatches", {
  wrong_type_data <- sample_interactions()
  wrong_type_data$page_number <- as.character(wrong_type_data$page_number)

  result <- validate_interactions_schema(wrong_type_data, strict = FALSE)

  expect_true(any(grepl("page_number.*should be numeric", result$warnings)))
})

test_that("validate_interactions_schema detects empty required fields", {
  empty_fields_data <- sample_interactions()
  empty_fields_data$bat_species_scientific_name[1] <- ""
  empty_fields_data$bat_species_common_name[2] <- NA

  result <- validate_interactions_schema(empty_fields_data, strict = FALSE)

  expect_true(any(grepl("empty.*bat_species", result$warnings)))
})

test_that("get_schema_columns returns expected column names", {
  columns <- get_schema_columns()

  expect_type(columns, "character")
  expect_true("bat_species_scientific_name" %in% columns)
  expect_true("bat_species_common_name" %in% columns)
  expect_true("interacting_organism_scientific_name" %in% columns)
  expect_true("page_number" %in% columns)
})

test_that("get_schema_types returns correct SQL types", {
  types <- get_schema_types()

  expect_type(types, "character")
  expect_equal(types["bat_species_scientific_name"], c(bat_species_scientific_name = "TEXT"))
  expect_equal(types["page_number"], c(page_number = "INTEGER"))
  expect_equal(types["publication_year"], c(publication_year = "INTEGER"))
})

test_that("get_required_columns returns required fields", {
  required <- get_required_columns()

  expect_type(required, "character")
  expect_true("bat_species_scientific_name" %in% required)
  expect_true("bat_species_common_name" %in% required)
})

test_that("filter_to_schema_columns removes unknown columns", {
  data_with_extra <- sample_interactions()
  data_with_extra$unknown_col1 <- "test1"
  data_with_extra$unknown_col2 <- "test2"

  filtered <- filter_to_schema_columns(data_with_extra)

  expect_false("unknown_col1" %in% names(filtered))
  expect_false("unknown_col2" %in% names(filtered))
  expect_true("bat_species_scientific_name" %in% names(filtered))
})

test_that("filter_to_schema_columns preserves all schema columns present", {
  data <- sample_interactions()
  filtered <- filter_to_schema_columns(data)

  expect_equal(names(filtered), names(data))
  expect_equal(nrow(filtered), nrow(data))
})

test_that("add_missing_schema_columns adds missing columns with correct types", {
  minimal <- minimal_interactions()
  enhanced <- add_missing_schema_columns(minimal)

  schema_cols <- get_schema_columns()
  expect_true(all(schema_cols %in% names(enhanced)))

  # Check that added columns have correct NA types
  expect_type(enhanced$interacting_organism_scientific_name, "character")
  expect_type(enhanced$page_number, "integer")
})

test_that("add_missing_schema_columns doesn't overwrite existing columns", {
  data <- sample_interactions()
  original_bat_name <- data$bat_species_scientific_name[1]

  enhanced <- add_missing_schema_columns(data)

  expect_equal(enhanced$bat_species_scientific_name[1], original_bat_name)
})

test_that("validate_and_prepare_for_db filters and adds columns", {
  data_with_extra <- sample_interactions()
  data_with_extra$unknown_field <- "test"
  data_with_extra$bat_species_scientific_name <- NULL  # Remove a schema column

  prepared <- validate_and_prepare_for_db(data_with_extra)

  expect_false("unknown_field" %in% names(prepared))
  expect_true("bat_species_scientific_name" %in% names(prepared))
  expect_true(all(is.na(prepared$bat_species_scientific_name)))
})

test_that("get_database_schema returns comprehensive schema info", {
  schema <- get_database_schema()

  expect_type(schema, "list")
  expect_true("columns" %in% names(schema))
  expect_true("types" %in% names(schema))
  expect_true("required" %in% names(schema))

  expect_type(schema$columns, "character")
  expect_type(schema$types, "character")
  expect_type(schema$required, "character")
})
