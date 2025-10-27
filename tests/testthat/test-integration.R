# Integration Tests
# Tests mirror the workflow: OCR → Audit → Extract → Refine → Full Pipeline
# Each test verifies API response structure only, not content accuracy

test_that("step 1: ohseer package is available", {
  # Verify ohseer dependency is installed
  expect_true(requireNamespace("ohseer", quietly = TRUE))

  # Note: Actual OCR testing requires:
  # 1. A test PDF file
  # 2. Mistral API key (MISTRAL_API_KEY)
  # 3. result <- ohseer::mistral_ocr("test.pdf")
  # When those are available, expand this test
})

test_that("step 2: OCR audit returns valid structure", {
  skip_if_not(has_api_keys(), "API keys not available")

  ocr_content <- sample_ocr_content()

  result <- perform_ocr_audit(ocr_content)

  # Check structure
  expect_type(result, "list")
  expect_true("audited_markdown" %in% names(result))
  expect_type(result$audited_markdown, "character")
  expect_true(nchar(result$audited_markdown) > 0)
})

test_that("step 3: extraction returns valid structure", {
  skip_if_not(has_api_keys(), "API keys not available")

  ocr_content <- sample_ocr_content()

  result <- extract_records(
    document_content = ocr_content,
    existing_interactions = NA
  )

  # Check structure, not content
  expect_type(result, "list")
  expect_true("success" %in% names(result))
  expect_true("interactions" %in% names(result))

  if (result$success) {
    expect_true(is.data.frame(result$interactions))
  }
})

test_that("step 4: refinement returns valid structure", {
  skip_if_not(has_api_keys(), "API keys not available")

  records <- sample_records()
  ocr_content <- sample_ocr_content()

  result <- refine_records(
    interactions = records,
    markdown_text = ocr_content
  )

  # Check structure, not content
  expect_type(result, "list")
  expect_true("success" %in% names(result))
  expect_true("interactions" %in% names(result))

  if (result$success) {
    expect_true(is.data.frame(result$interactions))
  }
})

test_that("step 5: full pipeline with process_document", {
  skip_if_not(has_api_keys(), "API keys not available")
  skip("Requires test PDF and ohseer package")

  # This would test the complete workflow:
  # 1. OCR the PDF (ohseer::mistral_ocr)
  # 2. Audit OCR output (perform_ocr_audit)
  # 3. Extract records (extract_records)
  # 4. Refine records (refine_records)
  # 5. Save to database

  # test_pdf <- system.file("testdata", "sample.pdf", package = "ecoextract")
  # db_path <- withr::local_tempfile(fileext = ".sqlite")
  #
  # result <- process_document(test_pdf, db_path)
  #
  # expect_type(result, "list")
  # expect_true(result$success)
  # expect_true(file.exists(db_path))
  #
  # # Verify data was saved to database
  # con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  # withr::defer(DBI::dbDisconnect(con))
  # docs <- DBI::dbReadTable(con, "documents")
  # records <- DBI::dbReadTable(con, "interactions")
  # expect_equal(nrow(docs), 1)
  # expect_true(nrow(records) > 0)
})
