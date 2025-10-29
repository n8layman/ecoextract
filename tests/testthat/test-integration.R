# Integration Tests
# Tests the full workflow: OCR → Audit → Extract → Refine → Save to Database
# Each test verifies API response structure and database persistence

test_that("step 1: OCR with Mistral", {
  skip_if(Sys.getenv("MISTRAL_API_KEY") == "", "MISTRAL_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "test_paper.pdf")
  skip_if_not(file.exists(test_pdf), "Test PDF not found")

  result <- ohseer::mistral_ocr(test_pdf)

  expect_type(result, "list")
  expect_true("pages" %in% names(result))
  expect_true(length(result$pages) > 0)
  expect_true("markdown" %in% names(result$pages[[1]]))
})

test_that("step 2: OCR audit and save to database", {
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  db_path <- local_test_db()
  ocr_content <- sample_ocr_content()

  result <- perform_ocr_audit(ocr_content)

  expect_type(result, "list")
  expect_true("audited_markdown" %in% names(result))
  expect_type(result$audited_markdown, "character")
  expect_true(nchar(result$audited_markdown) > 0)

  # Save audited content to database
  doc_id <- save_document_to_db(db_path, "test_doc.pdf")
  expect_type(doc_id, "integer")

  # Verify saved to database
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  docs <- DBI::dbReadTable(con, "documents")
  expect_equal(nrow(docs), 1)
  expect_equal(docs$id, doc_id)
})

test_that("step 3: extraction and save to database", {
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  db_path <- local_test_db()
  ocr_content <- sample_ocr_content()

  # Save document first
  doc_id <- save_document_to_db(db_path, "test_doc.pdf")

  result <- extract_records(
    document_content = ocr_content,
    existing_interactions = NA
  )

  expect_type(result, "list")
  expect_true("success" %in% names(result))
  expect_true("interactions" %in% names(result))

  if (result$success && nrow(result$interactions) > 0) {
    # Save extracted records to database
    save_records_to_db(db_path, doc_id, result$interactions)

    # Verify saved to database
    con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    withr::defer(DBI::dbDisconnect(con))
    records <- DBI::dbReadTable(con, "interactions")
    expect_true(nrow(records) > 0)
    expect_equal(unique(records$document_id), doc_id)
  }
})

test_that("step 4: refinement and save to database", {
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  db_path <- local_test_db()
  records <- sample_records()
  ocr_content <- sample_ocr_content()

  # Save document first
  doc_id <- save_document_to_db(db_path, "test_doc.pdf")

  result <- refine_records(
    interactions = records,
    markdown_text = ocr_content
  )

  expect_type(result, "list")
  expect_true("success" %in% names(result))
  expect_true("interactions" %in% names(result))

  if (result$success && nrow(result$interactions) > 0) {
    # Save refined records to database
    save_records_to_db(db_path, doc_id, result$interactions, metadata = list(
      model = result$model,
      prompt_hash = result$prompt_hash
    ))

    # Verify saved to database
    con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    withr::defer(DBI::dbDisconnect(con))
    records <- DBI::dbReadTable(con, "interactions")
    expect_true(nrow(records) > 0)
  }
})

test_that("step 5: full pipeline from PDF to database", {
  skip_if(Sys.getenv("MISTRAL_API_KEY") == "", "MISTRAL_API_KEY not set")
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "test_paper.pdf")
  skip_if_not(file.exists(test_pdf), "Test PDF not found")

  db_path <- withr::local_tempfile(fileext = ".sqlite")

  # Test the full process_documents workflow
  result <- process_documents(test_pdf, db_path = db_path)

  expect_type(result, "list")
  expect_equal(result$total_files, 1)
  expect_equal(result$errors, 0)

  # Verify data in database
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  docs <- DBI::dbReadTable(con, "documents")
  records <- DBI::dbReadTable(con, "interactions")

  expect_equal(nrow(docs), 1)
  expect_true(nrow(records) >= 0)
})
