# Human Review and Accuracy Tests
# Tests for save_document workflow, edit tracking, and accuracy metrics

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
    "extraction_timestamp", "fields_changed_count", "human_edited", "deleted_by_user", "added_by_user"))
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
    "extraction_timestamp", "fields_changed_count", "human_edited", "deleted_by_user", "added_by_user"))

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

# Accuracy Metrics -------------------------------------------------------------

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
  expect_true("records_with_edits" %in% names(result))
  expect_true("column_edits" %in% names(result))

  # Field-level metrics
  expect_true("total_fields" %in% names(result))
  expect_true("correct_fields" %in% names(result))
  expect_true("field_precision" %in% names(result))
  expect_true("field_recall" %in% names(result))
  expect_true("field_f1" %in% names(result))

  # Record detection metrics
  expect_true("records_found" %in% names(result))
  expect_true("records_missed" %in% names(result))
  expect_true("records_hallucinated" %in% names(result))
  expect_true("detection_precision" %in% names(result))
  expect_true("detection_recall" %in% names(result))
  expect_true("perfect_record_rate" %in% names(result))

  # Per-column accuracy
  expect_true("column_accuracy" %in% names(result))

  # Edit severity
  expect_true("major_edits" %in% names(result))
  expect_true("minor_edits" %in% names(result))
  expect_true("major_edit_rate" %in% names(result))
  expect_true("avg_edits_per_document" %in% names(result))
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
  expect_equal(result_after$records_with_edits, 0)
  expect_equal(result_after$records_found, nrow(records))
  expect_equal(result_after$detection_recall, 1.0)
  expect_equal(result_after$field_precision, 1.0)
})
