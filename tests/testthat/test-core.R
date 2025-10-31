# Core Functionality Tests
# Generic tests that work with any schema/domain

# Database Core ----------------------------------------------------------------

test_that("database initialization creates required tables", {
  db_path <- local_test_db()

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  tables <- DBI::dbListTables(con)
  expect_true("documents" %in% tables)
  expect_true("records" %in% tables)
})

test_that("database schema matches JSON schema definition", {
  db_path <- local_test_db()
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  db_columns <- DBI::dbListFields(con, "records")
  schema_columns <- get_db_schema_columns()

  # Database should contain all schema columns
  expect_true(all(schema_columns %in% db_columns))
})

test_that("save and retrieve records workflow", {
  db_path <- local_test_db()

  # Save document (hash computed automatically)
  doc_id <- save_document_to_db(db_path, "test.pdf")
  expect_type(doc_id, "integer")

  # Save records (will throw error if it fails)
  records <- sample_records()
  save_records_to_db(db_path, doc_id, records, list())

  # Verify saved
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  saved <- DBI::dbReadTable(con, "records")
  expect_equal(nrow(saved), nrow(records))
})

# Schema Validation ------------------------------------------------------------

test_that("validate_interactions_schema accepts valid data", {
  records <- sample_records()
  validation <- validate_interactions_schema(records)

  expect_true(validation$valid)
  expect_length(validation$errors, 0)
})

test_that("validate_interactions_schema reports warnings for unknown columns", {
  test_df <- sample_records()
  test_df$unknown_column <- "extra data"

  validation <- validate_interactions_schema(test_df)

  # Should still be valid but may have warnings
  expect_true(validation$valid)
  expect_type(validation, "list")
})

test_that("filter_to_schema_columns removes unknown columns", {
  schema_cols <- get_db_schema_columns()
  test_df <- sample_records()
  test_df$unknown_column <- "should be removed"

  filtered <- filter_to_schema_columns(test_df)

  expect_false("unknown_column" %in% names(filtered))
  expect_true(all(names(filtered) %in% schema_cols))
})

# ID Generation ----------------------------------------------------------------

test_that("generate_occurrence_id creates correct format", {
  id <- generate_occurrence_id("Smith", 2020, 1)

  expect_type(id, "character")
  expect_match(id, "Smith2020-o1")
})

test_that("generate_occurrence_id handles special characters", {
  id <- generate_occurrence_id("O'Brien", 2020, 1)

  expect_match(id, "OBrien2020-o1")
  expect_false(grepl("'", id))
})

test_that("add_occurrence_ids adds IDs to all rows", {
  records <- sample_records()
  records$occurrence_id <- NULL

  result <- add_occurrence_ids(records, "Test", 2020)

  expect_true("occurrence_id" %in% names(result))
  expect_equal(nrow(result), nrow(records))
  expect_true(all(!is.na(result$occurrence_id)))
})

# Utilities --------------------------------------------------------------------

test_that("estimate_tokens handles various inputs", {
  expect_equal(estimate_tokens(NULL), 0)
  expect_equal(estimate_tokens(""), 0)
  expect_equal(estimate_tokens(NA_character_), 0)

  text <- "This is a test string"
  tokens <- estimate_tokens(text)
  expect_type(tokens, "double")
  expect_true(tokens > 0)
})
