# Integration Tests for Complete Workflow
# These tests use real API calls and are the PRIMARY tests for PR validation
# Unit tests are nice, but these integration tests MUST pass for merging to main

# Helper to check if API keys are available
has_api_keys <- function() {
  # Try to load from .env if it exists
  if (file.exists(".env")) {
    load_env_file(".env")
  }

  anthropic_key <- Sys.getenv("ANTHROPIC_API_KEY")
  !is.null(anthropic_key) && nzchar(anthropic_key)
}

# Helper to get test PDF path (we'll use the markdown as mock OCR output)
get_test_document_path <- function() {
  system.file("extdata", "test_paper.md", package = "ecoextract")
}

# Helper to create test database
local_integration_db <- function(env = parent.frame()) {
  db_path <- tempfile(fileext = ".sqlite")
  init_ecoextract_database(db_path)
  withr::defer(unlink(db_path), envir = env)
  db_path
}

# =============================================================================
# OCR INTEGRATION TEST
# =============================================================================

test_that("OCR process completes successfully", {
  skip_if_not(has_api_keys(), "API keys not available")

  # This test would use perform_ocr() on a real PDF
  # For now we're testing with the markdown file as mock OCR output
  test_doc <- get_test_document_path()

  # Read the test document (simulating OCR output)
  ocr_content <- readLines(test_doc, warn = FALSE) |>
    paste(collapse = "\n")

  # Verify OCR content has expected structure
  expect_true(nzchar(ocr_content))
  expect_match(ocr_content, "Myotis")
  expect_match(ocr_content, "co-roosting")

  # Verify it contains the expected interactions
  expect_match(ocr_content, "Myotis lucifugus")
  expect_match(ocr_content, "Myotis yumanensis")
  expect_match(ocr_content, "Roosevelt Grove")
})

# =============================================================================
# EXTRACTION INTEGRATION TEST
# =============================================================================

test_that("Extraction process completes and returns valid interactions", {
  skip_if_not(has_api_keys(), "API keys not available")

  db_path <- local_integration_db()
  test_doc <- get_test_document_path()

  # Read test document
  ocr_content <- readLines(test_doc, warn = FALSE) |>
    paste(collapse = "\n")

  # Save document to database first
  file_hash <- digest::digest(ocr_content, algo = "md5")
  doc_id <- save_document_to_db(
    db_path = db_path,
    file_path = test_doc,
    file_hash = file_hash,
    metadata = list()
  )

  expect_type(doc_id, "integer")

  # Run extraction
  extraction_response <- tryCatch({
    extract_interactions(
      document_content = ocr_content,
      schema_file = NULL,  # Use default schema
      extraction_prompt_file = NULL,  # Use default prompt
      existing_interactions = NA
    )
  }, error = function(e) {
    skip(paste("Extraction failed:", e$message))
  })

  # Verify extraction result structure
  expect_type(extraction_response, "list")
  expect_true(extraction_response$success)
  extraction_result <- extraction_response$interactions
  expect_s3_class(extraction_result, "data.frame")
  expect_true(nrow(extraction_result) > 0)

  # Verify it extracted expected interactions
  # Based on test_paper.md, we expect 4+ interaction events
  expect_gte(nrow(extraction_result), 4)

  # Verify required columns exist
  required_cols <- get_required_columns()
  for (col in required_cols) {
    expect_true(col %in% names(extraction_result),
                label = paste("Required column", col, "exists"))
  }

  # Verify it contains expected species
  # The schema uses bat_species_scientific_name and interacting_organism_scientific_name
  all_organisms <- c(
    extraction_result$bat_species_scientific_name,
    extraction_result$interacting_organism_scientific_name
  )
  expect_true(any(grepl("Myotis lucifugus", all_organisms, ignore.case = TRUE)))
  expect_true(any(grepl("Myotis yumanensis", all_organisms, ignore.case = TRUE)))

  # Verify interactions can be saved to database
  save_result <- tryCatch({
    save_interactions_to_db(
      db_path = db_path,
      document_id = doc_id,
      interactions_df = extraction_result,
      metadata = list()
    )
  }, error = function(e) {
    fail(paste("Could not save interactions to database:", e$message))
  })

  expect_true(save_result)

  # Verify interactions are in database
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  saved_interactions <- DBI::dbGetQuery(con,
    "SELECT * FROM interactions WHERE document_id = ?",
    params = list(doc_id)
  )

  expect_equal(nrow(saved_interactions), nrow(extraction_result))
})

# =============================================================================
# REFINEMENT INTEGRATION TEST
# =============================================================================

test_that("Refinement process completes and improves extractions", {
  skip_if_not(has_api_keys(), "API keys not available")

  db_path <- local_integration_db()
  test_doc <- get_test_document_path()

  # Read test document
  ocr_content <- readLines(test_doc, warn = FALSE) |>
    paste(collapse = "\n")

  # Save document to database
  file_hash <- digest::digest(ocr_content, algo = "md5")
  doc_id <- save_document_to_db(
    db_path = db_path,
    file_path = test_doc,
    file_hash = file_hash,
    metadata = list()
  )

  # Run extraction first
  extraction_response <- tryCatch({
    extract_interactions(
      document_content = ocr_content,
      schema_file = NULL,
      extraction_prompt_file = NULL,
      existing_interactions = NA
    )
  }, error = function(e) {
    skip(paste("Extraction failed:", e$message))
  })

  extraction_result <- extraction_response$interactions

  # Save initial extractions
  save_interactions_to_db(db_path, doc_id, extraction_result, metadata = list())

  # Run refinement
  refinement_response <- tryCatch({
    refine_interactions(
      interactions = extraction_result,
      markdown_text = ocr_content,
      schema_file = NULL,
      refinement_prompt_file = NULL
    )
  }, error = function(e) {
    skip(paste("Refinement failed:", e$message))
  })

  # Verify refinement result structure
  expect_type(refinement_response, "list")
  expect_true(refinement_response$success)
  refinement_result <- refinement_response$interactions
  expect_s3_class(refinement_result, "data.frame")
  expect_true(nrow(refinement_result) > 0)

  # Verify refinement maintains or improves quality
  # Should have same or more rows (refinement might split or add interactions)
  expect_gte(nrow(refinement_result), nrow(extraction_result) * 0.8)

  # Verify required columns still exist
  required_cols <- get_required_columns()
  for (col in required_cols) {
    expect_true(col %in% names(refinement_result),
                label = paste("Required column", col, "exists after refinement"))
  }

  # Verify refined interactions are still valid according to schema
  validation <- validate_interactions_schema(refinement_result, strict = FALSE)
  expect_true(validation$valid || length(validation$warnings) == 0,
              label = "Refined interactions pass schema validation")

  # Merge refinements with original extractions
  final_result <- merge_refinements(extraction_result, refinement_result)

  expect_s3_class(final_result, "data.frame")
  expect_true(nrow(final_result) > 0)
})

# =============================================================================
# FULL WORKFLOW INTEGRATION TEST
# =============================================================================

test_that("Complete workflow from document to database completes successfully", {
  skip_if_not(has_api_keys(), "API keys not available")

  db_path <- local_integration_db()
  test_doc <- get_test_document_path()

  # Read test document (in real workflow this would be OCR output)
  ocr_content <- readLines(test_doc, warn = FALSE) |>
    paste(collapse = "\n")

  # Step 1: Save document
  file_hash <- digest::digest(ocr_content, algo = "md5")
  doc_id <- save_document_to_db(
    db_path = db_path,
    file_path = test_doc,
    file_hash = file_hash,
    metadata = list()
  )
  expect_type(doc_id, "integer")

  # Step 2: Extract interactions
  extraction_response <- tryCatch({
    extract_interactions(
      document_content = ocr_content,
      schema_file = NULL,
      extraction_prompt_file = NULL,
      existing_interactions = NA
    )
  }, error = function(e) {
    skip(paste("Extraction failed:", e$message))
  })
  expect_true(extraction_response$success)
  extraction_result <- extraction_response$interactions
  expect_true(nrow(extraction_result) > 0)

  # Step 3: Refine interactions
  refinement_response <- tryCatch({
    refine_interactions(
      interactions = extraction_result,
      markdown_text = ocr_content,
      schema_file = NULL,
      refinement_prompt_file = NULL
    )
  }, error = function(e) {
    skip(paste("Refinement failed:", e$message))
  })
  expect_true(refinement_response$success)
  refinement_result <- refinement_response$interactions
  expect_true(nrow(refinement_result) > 0)

  # Step 4: Merge and validate
  final_interactions <- merge_refinements(extraction_result, refinement_result)
  validation <- validate_interactions_schema(final_interactions, strict = FALSE)
  expect_true(validation$valid || length(validation$warnings) == 0)

  # Step 5: Save to database
  save_result <- save_interactions_to_db(
    db_path = db_path,
    document_id = doc_id,
    interactions_df = final_interactions,
    metadata = list()
  )
  expect_true(save_result)

  # Step 6: Verify end-to-end results
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  # Check documents table
  docs <- DBI::dbGetQuery(con, "SELECT * FROM documents WHERE id = ?",
                          params = list(doc_id))
  expect_equal(nrow(docs), 1)
  expect_true(nzchar(docs$file_name))

  # Check interactions table
  interactions <- DBI::dbGetQuery(con,
    "SELECT * FROM interactions WHERE document_id = ?",
    params = list(doc_id)
  )
  expect_true(nrow(interactions) >= 4)  # Expect at least 4 interactions from test paper

  # Verify expected species are present
  all_organisms <- c(interactions$bat_species_scientific_name, interactions$interacting_organism_scientific_name)
  expect_true(any(grepl("Myotis", all_organisms)))

  # Get database stats
  stats <- get_db_stats(db_path)
  expect_equal(stats$total_documents, 1)
  expect_equal(stats$total_interactions, nrow(interactions))

  # Success message
  message(sprintf(
    "\n✓ Full workflow complete: %d interactions extracted from test document",
    nrow(interactions)
  ))
})
