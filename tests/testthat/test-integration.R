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
