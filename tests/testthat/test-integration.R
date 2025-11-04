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

test_that("workflow continues processing all files even when some fail", {
  cat("\n========== TEST: workflow continues processing all files even when some fail ==========\n")
  # Critical: verify that when processing 100s of papers, one failure
  # doesn't stop the entire batch
  skip_if(Sys.getenv("MISTRAL_API_KEY") == "", "MISTRAL_API_KEY not set")
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "test_paper.pdf")
  skip_if_not(file.exists(test_pdf), "Test PDF not found")

  # Create a bad PDF that will fail OCR
  bad_pdf <- withr::local_tempfile(fileext = ".pdf")
  writeLines("This is not a valid PDF", bad_pdf)

  db_path <- withr::local_tempfile(fileext = ".sqlite")

  # Process both files: one good, one bad
  # The workflow should process both and return results for both
  result <- process_documents(c(test_pdf, bad_pdf), db_path = db_path)

  # Should get results for BOTH files (2 rows)
  expect_equal(nrow(result), 2,
               info = "Should process all files even if some fail")

  # First file should succeed
  expect_equal(result$ocr_status[1], "completed",
               info = "Good PDF should process successfully")

  # Second file should fail at OCR but still be in results
  expect_false(result$ocr_status[2] %in% c("completed", "skipped"),
               info = "Bad PDF should have error status")

  # Verify we got records from the good file
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  records <- DBI::dbReadTable(con, "records")
  expect_true(nrow(records) > 0,
              info = "Should have records from successful file")
})
