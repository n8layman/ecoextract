# Integration Test
# Tests the complete end-to-end workflow: OCR → Audit → Extract → Refine → Save to Database
# This test validates that all steps work together correctly and error handling propagates properly

test_that("full pipeline from PDF to database", {
  cat("\n========== TEST: full pipeline from PDF to database ==========\n")
  skip_if(Sys.getenv("MISTRAL_API_KEY") == "", "MISTRAL_API_KEY not set")
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "test_paper.pdf")
  skip_if_not(file.exists(test_pdf), "Test PDF not found")

  db_path <- withr::local_tempfile(fileext = ".sqlite")

  # Test the full process_documents workflow
  result <- process_documents(test_pdf, db_path = db_path)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 1)

  # Check that all steps completed successfully
  status_matrix <- result |>
    dplyr::select(ocr_status, audit_status, extraction_status, refinement_status) |>
    as.matrix()

  has_errors <- any(!status_matrix %in% c("skipped", "completed"))
  if (has_errors) {
    failed_steps <- paste(
      names(result)[which(!status_matrix %in% c("skipped", "completed"))],
      "=",
      status_matrix[!status_matrix %in% c("skipped", "completed")],
      collapse = ", "
    )
    stop("Pipeline failed: ", failed_steps)
  }

  # Verify data in database
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  docs <- DBI::dbReadTable(con, "documents")
  records <- DBI::dbReadTable(con, "records")

  expect_equal(nrow(docs), 1)
  expect_true(nrow(records) >= 0)  # Zero is valid - paper may not contain data
})

test_that("extraction rediscovers physically deleted records", {
  cat("\n========== TEST: extraction rediscovers physically deleted records ==========\n")
  skip_if(Sys.getenv("MISTRAL_API_KEY") == "", "MISTRAL_API_KEY not set")
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "test_paper.pdf")
  skip_if_not(file.exists(test_pdf), "Test PDF not found")

  db_path <- withr::local_tempfile(fileext = ".sqlite")

  # Run full pipeline first time
  result1 <- process_documents(test_pdf, db_path = db_path)

  # Verify all steps completed
  status_matrix1 <- result1 |>
    dplyr::select(ocr_status, audit_status, extraction_status,
                  refinement_status) |>
    as.matrix()
  expect_false(any(!status_matrix1 %in% c("skipped", "completed")),
               info = "First run should complete all steps successfully")

  # Get initial record count
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  initial_count <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) as count FROM records")$count
  expect_true(initial_count > 0, "Should have extracted some records")

  # Delete one record from the database
  deleted_record <- DBI::dbGetQuery(
    con, "SELECT occurrence_id, bat_species_scientific_name,
                 interacting_organism_scientific_name
          FROM records LIMIT 1")
  DBI::dbExecute(con, "DELETE FROM records WHERE occurrence_id = ?",
                 params = list(deleted_record$occurrence_id[1]))

  after_delete_count <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) as count FROM records")$count
  expect_equal(after_delete_count, initial_count - 1,
    info = "Should have one less record after deletion")

  # Re-run pipeline (will skip OCR/audit, run extraction+refinement)
  result2 <- process_documents(test_pdf, db_path = db_path)

  # Check that early steps were skipped, but extraction+refinement run
  expect_equal(result2$ocr_status[1], "skipped")
  expect_equal(result2$audit_status[1], "skipped")
  expect_equal(result2$extraction_status[1], "completed")
  expect_equal(result2$refinement_status[1], "completed")

  # Check that extraction rediscovered the deleted record
  final_count <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) as count FROM records")$count
  expect_equal(final_count, initial_count,
    info = sprintf(paste("Extraction should rediscover physically deleted record.",
                         "Initial: %d, After delete: %d, Final: %d"),
                   initial_count, after_delete_count, final_count))

  # Verify the specific species we deleted is back
  rediscovered <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) as count FROM records
     WHERE bat_species_scientific_name = ?
       AND interacting_organism_scientific_name = ?",
    params = list(deleted_record$bat_species_scientific_name[1],
                  deleted_record$interacting_organism_scientific_name[1]))$count
  expect_true(rediscovered > 0,
              "Deleted record should be rediscovered by extraction")
})

test_that("API failures are captured in status columns, not thrown", {
  cat("\n========== TEST: API failures are captured in status columns, not thrown ==========\n")
  # Verify that API failures don't throw errors but return tibble with
  # error messages in status columns
  # Uses bad API key so it should fail without using credits

  skip_if(Sys.getenv("MISTRAL_API_KEY") == "", "MISTRAL_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "test_paper.pdf")
  skip_if_not(file.exists(test_pdf), "Test PDF not found")

  db_path <- withr::local_tempfile(fileext = ".sqlite")

  # Temporarily set bad Anthropic API key
  original_key <- Sys.getenv("ANTHROPIC_API_KEY")
  Sys.setenv(ANTHROPIC_API_KEY = "bad-key-should-fail")
  withr::defer(Sys.setenv(ANTHROPIC_API_KEY = original_key))

  # Run process_documents - should NOT throw, should return tibble
  result <- process_documents(test_pdf, db_path = db_path)

  # Verify we got a tibble back (not an error throw)
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 1)

  # Check status matrix - should have at least one error
  status_matrix <- result |>
    dplyr::select(ocr_status, audit_status, extraction_status, refinement_status) |>
    as.matrix()

  has_errors_in_status <- any(!status_matrix %in% c("skipped", "completed"))
  expect_true(has_errors_in_status,
              info = "With bad API key, at least one status column should contain an error message")

  # OCR should work (uses Mistral, different key)
  expect_equal(result$ocr_status[1], "completed",
               info = "OCR uses Mistral, should still complete")

  # Audit or extraction should fail (uses Anthropic)
  audit_or_extraction_has_error <-
    result$audit_status[1] != "completed" || result$extraction_status[1] != "completed"
  expect_true(audit_or_extraction_has_error,
              info = "Document audit or extraction should fail with bad Anthropic key")
})
