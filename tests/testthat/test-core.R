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

  # Create temporary test file
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)

  # Save document (hash computed automatically)
  doc_id <- save_document_to_db(db_path, test_file)
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

# Schema Validation tests removed - schema.R was domain-specific legacy code

# ID Generation ----------------------------------------------------------------

test_that("generate_record_id creates correct format", {
  id <- generate_record_id("Smith", 2020, 1)

  expect_type(id, "character")
  expect_match(id, "Smith_2020_1_r1")
})

test_that("generate_record_id handles special characters", {
  id <- generate_record_id("O'Brien", 2020, 1)

  expect_match(id, "OBrien_2020_1_r1")
  expect_false(grepl("'", id))
})

test_that("add_record_ids adds IDs to all rows", {
  records <- sample_records()
  records$record_id <- NULL

  result <- add_record_ids(records, "Test", 2020)

  expect_true("record_id" %in% names(result))
  expect_equal(nrow(result), nrow(records))
  expect_true(all(!is.na(result$record_id)))
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

# Human Review Workflow --------------------------------------------------------

test_that("save_document updates reviewed_at timestamp", {
  db_path <- local_test_db()

  # Create test document
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)

  # Save initial records
  records <- sample_records()
  save_records_to_db(db_path, doc_id, records, list())

  # Verify reviewed_at is NULL initially
  doc_before <- get_documents(doc_id, db_path)
  expect_true(is.na(doc_before$reviewed_at))

  # Save document (mark as reviewed)
  save_document(doc_id, records, records, db_path)

  # Verify reviewed_at is now set

  doc_after <- get_documents(doc_id, db_path)
  expect_false(is.na(doc_after$reviewed_at))
})

test_that("save_document marks modified records as human_edited", {
  db_path <- local_test_db()

  # Setup
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)

  records <- sample_records()
  save_records_to_db(db_path, doc_id, records, list())

  # Fetch back from DB to get generated record_ids
  original <- get_records(doc_id, db_path)

  # Modify a record
  edited <- original
  schema_cols <- setdiff(names(edited), c("id", "record_id", "document_id",
    "extraction_timestamp", "llm_model_version", "prompt_hash",
    "fields_changed_count", "human_edited", "deleted_by_user", "added_by_user"))
  if (length(schema_cols) > 0) {
    edited[[schema_cols[1]]][1] <- "EDITED_VALUE"
  }

  # Save with changes
  save_document(doc_id, edited, original, db_path)

  # Verify human_edited timestamp is set
  saved <- get_records(doc_id, db_path)
  expect_false(is.na(saved$human_edited[1]))
})

test_that("save_document marks deleted records as deleted_by_user", {
  db_path <- local_test_db()

  # Setup
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)

  records <- sample_records()
  save_records_to_db(db_path, doc_id, records, list())

  # Fetch back from DB to get generated record_ids
  original <- get_records(doc_id, db_path)

  # Delete one record (remove from dataframe)
  deleted_id <- original$record_id[1]
  edited <- original[-1, , drop = FALSE]

  # Save with deletion
  save_document(doc_id, edited, original, db_path)

  # Verify deleted_by_user timestamp is set
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  saved <- DBI::dbReadTable(con, "records")
  deleted_record <- saved[saved$record_id == deleted_id, ]
  expect_false(is.na(deleted_record$deleted_by_user))
})

test_that("save_document without original_df only updates reviewed_at", {
  db_path <- local_test_db()

  # Setup
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)

  records <- sample_records()
  save_records_to_db(db_path, doc_id, records, list())

  # Fetch records back from DB
  current_records <- get_records(doc_id, db_path)

  # Save without original (just mark reviewed)
  save_document(doc_id, current_records, db_conn = db_path)

  # Verify reviewed_at is set
  doc <- get_documents(doc_id, db_path)
  expect_false(is.na(doc$reviewed_at))

  # Verify records unchanged (human_edited should be FALSE - no edits in record_edits table)
  saved <- get_records(doc_id, db_path)
  expect_true(all(!saved$human_edited))
})

# Accuracy Tracking -------------------------------------------------------------

test_that("database initialization creates record_edits table", {
  db_path <- local_test_db()

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  tables <- DBI::dbListTables(con)
  expect_true("record_edits" %in% tables)

  # Verify table structure
  cols <- DBI::dbListFields(con, "record_edits")
  expect_true("record_id" %in% cols)
  expect_true("column_name" %in% cols)
  expect_true("original_value" %in% cols)
  expect_true("edited_at" %in% cols)
})

test_that("save_document populates record_edits for modified columns", {
  db_path <- local_test_db()

  # Setup
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)

  records <- sample_records()
  save_records_to_db(db_path, doc_id, records, list())

  # Fetch back from DB
  original <- get_records(doc_id, db_path)

  # Modify a record
  edited <- original
  schema_cols <- setdiff(names(edited), c("id", "record_id", "document_id",
    "extraction_timestamp", "llm_model_version", "prompt_hash",
    "fields_changed_count", "human_edited", "deleted_by_user", "added_by_user"))

  if (length(schema_cols) > 0) {
    edited[[schema_cols[1]]][1] <- "MODIFIED_VALUE"
  }

  # Save with changes
  save_document(doc_id, edited, original, db_path)

  # Verify record_edits has entry
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  edits <- DBI::dbReadTable(con, "record_edits")
  expect_true(nrow(edits) > 0)
  expect_equal(edits$column_name[1], schema_cols[1])
  expect_false(is.na(edits$original_value[1]))
  expect_false(is.na(edits$edited_at[1]))
})

test_that("save_document sets added_by_user for new records", {
  db_path <- local_test_db()

  # Setup
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)

  records <- sample_records()
  save_records_to_db(db_path, doc_id, records, list())

  # Fetch back from DB
  original <- get_records(doc_id, db_path)

  # Add a new record (id = NA means new)
  # Create a copy of first row with NA id to signal it's new
  new_record <- original[1, , drop = FALSE]
  new_record$id <- NA
  new_record$record_id <- NA
  edited <- rbind(original, new_record)

  # Save with new record
  save_document(doc_id, edited, original, db_path)

  # Verify added_by_user is set for new record
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  all_records <- DBI::dbReadTable(con, "records")
  added_records <- all_records[all_records$added_by_user == 1, ]
  expect_true(nrow(added_records) > 0)
})

test_that("calculate_accuracy returns correct structure", {
  db_path <- local_test_db()

  result <- calculate_accuracy(db_path)

  # Should return list with expected fields
  expect_type(result, "list")

  # Raw counts
  expect_true("verified_documents" %in% names(result))
  expect_true("verified_records" %in% names(result))
  expect_true("model_extracted" %in% names(result))
  expect_true("human_added" %in% names(result))
  expect_true("deleted" %in% names(result))
  expect_true("edited" %in% names(result))
  expect_true("correct" %in% names(result))
  expect_true("column_edits" %in% names(result))

  # Derived rates
  expect_true("precision" %in% names(result))
  expect_true("recall" %in% names(result))
  expect_true("f1_score" %in% names(result))
  expect_true("column_accuracy" %in% names(result))
})

test_that("calculate_accuracy computes metrics from verified documents", {
  db_path <- local_test_db()

  # Setup: create document with records
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)

  records <- sample_records()
  save_records_to_db(db_path, doc_id, records, list())

  # Before review, should have 0 verified
  result_before <- calculate_accuracy(db_path)
  expect_equal(result_before$verified_documents, 0)

  # Mark as reviewed
  original <- get_records(doc_id, db_path)
  save_document(doc_id, original, original, db_path)

  # After review, should have verified records
  result_after <- calculate_accuracy(db_path)
  expect_equal(result_after$verified_documents, 1)
  expect_equal(result_after$verified_records, nrow(records))
  expect_equal(result_after$model_extracted, nrow(records))
  expect_equal(result_after$deleted, 0)
  expect_equal(result_after$human_added, 0)
  expect_equal(result_after$edited, 0)
  expect_equal(result_after$correct, nrow(records))
})
