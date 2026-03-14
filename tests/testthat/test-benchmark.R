# Tests for duplicate_for_trials() and scrub_pipeline_stages()

# Helper to insert a document with data at all pipeline stages
insert_full_document <- function(db_path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con))

  DBI::dbExecute(con, "
    INSERT INTO documents (
      file_name, file_path, file_hash, upload_timestamp,
      document_content, ocr_status, ocr_provider,
      title, first_author_lastname, authors, publication_year,
      metadata_status, metadata_llm_model,
      extraction_reasoning, records_extracted, extraction_status, extraction_llm_model,
      refinement_reasoning, refinement_status, refinement_llm_model,
      reviewed_at
    ) VALUES (
      'test.pdf', '/path/test.pdf', 'hash123', '2024-01-01',
      'OCR content here', 'completed', 'tensorlake',
      'Test Title', 'Smith', '[\"Smith, J.\"]', 2024,
      'completed', 'anthropic/claude-sonnet-4-5',
      'Reasoning text', 5, 'completed', 'anthropic/claude-sonnet-4-5',
      'Refine reasoning', 'completed', 'anthropic/claude-sonnet-4-5',
      '2024-06-15 12:00:00'
    )
  ")
}

test_that("duplicate_for_trials creates n trial databases", {
  db_path <- local_test_db()
  trial_dir <- withr::local_tempdir()

  trial_paths <- duplicate_for_trials(db_path, n = 3, through = "ocr", dir = trial_dir)

  expect_length(trial_paths, 3)
  expect_true(all(file.exists(trial_paths)))
  expect_true(all(grepl("_trial_[123]\\.", trial_paths)))
})

test_that("duplicate_for_trials accepts custom naming pattern", {
  db_path <- local_test_db()
  trial_dir <- withr::local_tempdir()

  trial_paths <- duplicate_for_trials(
    db_path, n = 2, through = "ocr", dir = trial_dir,
    pattern = "my_benchmark_{n}.sqlite"
  )

  expect_length(trial_paths, 2)
  expect_true(all(file.exists(trial_paths)))
  expect_equal(basename(trial_paths[1]), "my_benchmark_1.sqlite")
  expect_equal(basename(trial_paths[2]), "my_benchmark_2.sqlite")
})

test_that("duplicate_for_trials validates inputs", {
  expect_error(duplicate_for_trials("nonexistent.db", n = 1), "not found")

  db_path <- local_test_db()
  expect_error(duplicate_for_trials(db_path, n = 0), "positive integer")
  expect_error(duplicate_for_trials(db_path, n = -1), "positive integer")
  expect_error(duplicate_for_trials(db_path, n = 1, through = "invalid"), "should be one of")
})

test_that("duplicate_for_trials errors on existing trial files", {
  db_path <- local_test_db()
  trial_dir <- withr::local_tempdir()

  duplicate_for_trials(db_path, n = 2, through = "ocr", dir = trial_dir)
  expect_error(
    duplicate_for_trials(db_path, n = 2, through = "ocr", dir = trial_dir),
    "already exist"
  )
})

test_that("through = 'ocr' preserves OCR and clears later stages", {
  db_path <- local_test_db()
  insert_full_document(db_path)

  trial_dir <- withr::local_tempdir()
  trial_paths <- duplicate_for_trials(db_path, n = 1, through = "ocr", dir = trial_dir)

  con <- DBI::dbConnect(RSQLite::SQLite(), trial_paths[1])
  withr::defer(DBI::dbDisconnect(con))
  doc <- DBI::dbGetQuery(con, "SELECT * FROM documents LIMIT 1")

  # OCR preserved

  expect_equal(doc$document_content, "OCR content here")
  expect_equal(doc$ocr_status, "completed")

  # Metadata cleared
  expect_true(is.na(doc$title))
  expect_true(is.na(doc$metadata_status))

  # Extraction cleared
  expect_true(is.na(doc$extraction_status))
  expect_true(is.na(doc$extraction_reasoning))

  # Refinement cleared
  expect_true(is.na(doc$refinement_status))
})

test_that("through = 'metadata' preserves OCR + metadata and clears extraction", {
  db_path <- local_test_db()
  insert_full_document(db_path)

  trial_dir <- withr::local_tempdir()
  trial_paths <- duplicate_for_trials(db_path, n = 1, through = "metadata", dir = trial_dir)

  con <- DBI::dbConnect(RSQLite::SQLite(), trial_paths[1])
  withr::defer(DBI::dbDisconnect(con))
  doc <- DBI::dbGetQuery(con, "SELECT * FROM documents LIMIT 1")

  # OCR preserved
  expect_equal(doc$ocr_status, "completed")

  # Metadata preserved
  expect_equal(doc$title, "Test Title")
  expect_equal(doc$metadata_status, "completed")

  # Extraction cleared
  expect_true(is.na(doc$extraction_status))
  expect_true(is.na(doc$records_extracted))
})

test_that("through = 'extraction' preserves everything except refinement", {
  db_path <- local_test_db()
  insert_full_document(db_path)

  trial_dir <- withr::local_tempdir()
  trial_paths <- duplicate_for_trials(db_path, n = 1, through = "extraction", dir = trial_dir)

  con <- DBI::dbConnect(RSQLite::SQLite(), trial_paths[1])
  withr::defer(DBI::dbDisconnect(con))
  doc <- DBI::dbGetQuery(con, "SELECT * FROM documents LIMIT 1")

  # Everything preserved
  expect_equal(doc$extraction_status, "completed")
  expect_equal(doc$records_extracted, 5)

  # Refinement cleared
  expect_true(is.na(doc$refinement_status))
  expect_true(is.na(doc$refinement_reasoning))
})

test_that("records are deleted when through is 'ocr' or 'metadata'", {
  db_path <- local_test_db()

  # Insert document and records
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test", test_file)
  doc_id <- save_document_to_db(db_path, test_file)
  records <- sample_records()
  save_records_to_db(db_path, doc_id, records, list())

  # Verify records exist
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  initial_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM records")$n
  DBI::dbDisconnect(con)
  expect_gt(initial_count, 0)

  # through = "ocr" should delete records
  trial_dir <- withr::local_tempdir()
  trial_paths <- duplicate_for_trials(db_path, n = 1, through = "ocr", dir = trial_dir)

  con <- DBI::dbConnect(RSQLite::SQLite(), trial_paths[1])
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM records")$n, 0)
  DBI::dbDisconnect(con)
})

test_that("reviewed_at is always cleared", {
  db_path <- local_test_db()
  insert_full_document(db_path)

  # Even through = "extraction" should clear reviewed_at
  trial_dir <- withr::local_tempdir()
  trial_paths <- duplicate_for_trials(db_path, n = 1, through = "extraction", dir = trial_dir)

  con <- DBI::dbConnect(RSQLite::SQLite(), trial_paths[1])
  withr::defer(DBI::dbDisconnect(con))
  doc <- DBI::dbGetQuery(con, "SELECT reviewed_at FROM documents LIMIT 1")
  expect_true(is.na(doc$reviewed_at))
})
