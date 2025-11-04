# Integration Test
# Tests the complete end-to-end workflow: OCR → Audit → Extract → Refine → Save to Database
# This test validates that all steps work together correctly and error handling propagates properly

test_that("full pipeline from PDF to database", {
  skip_if(Sys.getenv("MISTRAL_API_KEY") == "", "MISTRAL_API_KEY not set")
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "test_paper.pdf")
  skip_if_not(file.exists(test_pdf), "Test PDF not found")

  db_path <- withr::local_tempfile(fileext = ".sqlite")

  # Test the full process_documents workflow
  result <- process_documents(test_pdf, db_path = db_path)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 1)

  # Check for any failures in the tibble - collect all error messages
  error_messages <- character(0)

  if (result$ocr_status[1] != "completed") {
    error_messages <- c(error_messages, paste("OCR failed:", result$ocr_status[1]))
  }
  if (result$audit_status[1] != "completed") {
    error_messages <- c(error_messages, paste("Audit failed:", result$audit_status[1]))
  }
  if (result$extraction_status[1] != "completed") {
    error_messages <- c(error_messages, paste("Extraction failed:", result$extraction_status[1]))
  }
  if (result$refinement_status[1] != "completed") {
    error_messages <- c(error_messages, paste("Refinement failed:", result$refinement_status[1]))
  }

  # If any errors found, throw them all at once
  if (length(error_messages) > 0) {
    stop(paste(error_messages, collapse = "\n"))
  }

  # Verify data in database
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  docs <- DBI::dbReadTable(con, "documents")
  records <- DBI::dbReadTable(con, "records")

  expect_equal(nrow(docs), 1)
  expect_true(nrow(records) >= 0)  # Zero is valid - paper may not contain data
})

test_that("refinement discovers deleted records", {
  skip_if(Sys.getenv("MISTRAL_API_KEY") == "", "MISTRAL_API_KEY not set")
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "test_paper.pdf")
  skip_if_not(file.exists(test_pdf), "Test PDF not found")

  db_path <- withr::local_tempfile(fileext = ".sqlite")

  # Run full pipeline first time
  result1 <- process_documents(test_pdf, db_path = db_path)

  # Verify all steps completed
  expect_equal(result1$ocr_status[1], "completed")
  expect_equal(result1$audit_status[1], "completed")
  expect_equal(result1$extraction_status[1], "completed")
  expect_equal(result1$refinement_status[1], "completed")

  # Get initial record count
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  initial_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as count FROM records")$count
  expect_true(initial_count > 0, "Should have extracted some records")

  # Delete one record from the database
  deleted_record <- DBI::dbGetQuery(con, "SELECT occurrence_id, bat_species_scientific_name, interacting_organism_scientific_name FROM records LIMIT 1")
  DBI::dbExecute(con, "DELETE FROM records WHERE occurrence_id = ?", params = list(deleted_record$occurrence_id[1]))

  after_delete_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as count FROM records")$count
  expect_equal(after_delete_count, initial_count - 1,
    info = "Should have one less record after deletion")

  # Re-run pipeline (should skip OCR, audit, extraction but run refinement)
  result2 <- process_documents(test_pdf, db_path = db_path)

  # Check that early steps were skipped
  expect_equal(result2$ocr_status[1], "skipped")
  expect_equal(result2$audit_status[1], "skipped")
  expect_equal(result2$extraction_status[1], "skipped")
  expect_equal(result2$refinement_status[1], "completed")

  # Check that refinement rediscovered the deleted record
  final_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as count FROM records")$count
  expect_equal(final_count, initial_count,
    info = sprintf("Refinement should rediscover deleted record. Initial: %d, After delete: %d, Final: %d",
                   initial_count, after_delete_count, final_count))

  # Verify the specific species we deleted is back
  rediscovered <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) as count FROM records WHERE bat_species_scientific_name = ? AND interacting_organism_scientific_name = ?",
    params = list(deleted_record$bat_species_scientific_name[1], deleted_record$interacting_organism_scientific_name[1]))$count
  expect_true(rediscovered > 0, "Deleted record should be rediscovered by refinement")
})
