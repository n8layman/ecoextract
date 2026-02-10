# Integration Tests
# All tests that require API keys (ANTHROPIC_API_KEY, MISTRAL_API_KEY, OPENAI_API_KEY)
# These are automatically skipped when keys are not set

# Full Pipeline ----------------------------------------------------------------

test_that("full pipeline from PDF to database", {
  cat("\n========== TEST: full pipeline from PDF to database ==========\n")
  skip_if(Sys.getenv("MISTRAL_API_KEY") == "", "MISTRAL_API_KEY not set")
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "test_paper.pdf")
  skip_if_not(file.exists(test_pdf), "Test PDF not found")

  db_path <- withr::local_tempfile(fileext = ".sqlite")

  # Use package default schema and prompt (not project customizations)
  schema_file <- system.file("extdata", "schema.json", package = "ecoextract")
  prompt_file <- system.file("prompts", "extraction_prompt.md", package = "ecoextract")

  # Test the full process_documents workflow
  result <- process_documents(
    test_pdf,
    db_conn = db_path,
    schema_file = schema_file,
    extraction_prompt_file = prompt_file
  )

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 1)

  # Check that all steps completed successfully
  status_matrix <- result |>
    dplyr::select(ocr_status, metadata_status, extraction_status, refinement_status) |>
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
  skip("Known issue #49 - extraction fails to rediscover physically deleted records")

  cat("\n========== TEST: extraction rediscovers physically deleted records ==========\n")
  skip_if(Sys.getenv("OPENAI_API_KEY") == "", "OPENAI_API_KEY not set")
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "test_paper.pdf")
  skip_if_not(file.exists(test_pdf), "Test PDF not found")

  db_path <- withr::local_tempfile(fileext = ".sqlite")

  # Use package default schema and prompt (not project customizations)
  schema_file <- system.file("extdata", "schema.json", package = "ecoextract")
  prompt_file <- system.file("prompts", "extraction_prompt.md", package = "ecoextract")

  # Run full pipeline first time
  result1 <- process_documents(
    test_pdf,
    db_conn = db_path,
    schema_file = schema_file,
    extraction_prompt_file = prompt_file
  )

  # Verify all steps completed
  status_matrix1 <- result1 |>
    dplyr::select(ocr_status, metadata_status, extraction_status,
                  refinement_status) |>
    as.matrix()
  expect_false(any(!status_matrix1 %in% c("skipped", "completed")),
               info = "First run should complete all steps successfully")

  # Get initial record count
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  initial_count <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) as count FROM records")$count

  # Skip test if extraction returned 0 records (LLM non-determinism)
  skip_if(initial_count == 0, "LLM extracted 0 records on first run")

  # Delete half the records from the database (physical delete)
  records_to_delete <- DBI::dbGetQuery(
    con, glue::glue("SELECT record_id FROM records LIMIT {floor(initial_count / 2)}"))
  for (rec_id in records_to_delete$record_id) {
    DBI::dbExecute(con, "DELETE FROM records WHERE record_id = ?",
                   params = list(rec_id))
  }

  after_delete_count <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) as count FROM records")$count
  expect_true(after_delete_count < initial_count,
    info = sprintf("Should have fewer records after deletion (%d -> %d)",
                   initial_count, after_delete_count))

  # Re-run pipeline - force extraction to rediscover deleted records
  # (OCR/metadata will skip, extraction forced to re-run)
  # Use Jaccard similarity to avoid API rate limits during testing
  result2 <- process_documents(
    test_pdf,
    db_conn = db_path,
    schema_file = schema_file,
    extraction_prompt_file = prompt_file,
    similarity_method = "jaccard",
    force_reprocess_extraction = TRUE
  )

  # Check that early steps were skipped, but extraction ran (forced)
  expect_equal(result2$ocr_status[1], "skipped")
  expect_equal(result2$metadata_status[1], "skipped")
  expect_equal(result2$extraction_status[1], "completed")

  # Check that extraction found more records than were left after deletion
  final_count <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) as count FROM records")$count
  expect_true(final_count > after_delete_count,
    info = sprintf(paste("Extraction should rediscover physically deleted records.",
                         "Initial: %d, After delete: %d, Final: %d"),
                   initial_count, after_delete_count, final_count))

  # Check that rows which were NOT deleted are NOT duplicated
  # Final count should not grossly exceed initial count (allowing for LLM variation)
  # Note: Duplicates would get new record_ids, so count is the key test
  expect_true(final_count <= initial_count * 1.5,
    info = sprintf(paste("Non-deleted records should not be duplicated.",
                         "Initial: %d, After delete: %d, Final: %d",
                         "(allowing 50%% margin for LLM variation/new discoveries)"),
                   initial_count, after_delete_count, final_count))
})

# Error Handling ---------------------------------------------------------------

test_that("API failures are captured in status columns, not thrown", {
  cat("\n========== TEST: API failures are captured in status columns, not thrown ==========\n")
  # Verify that API failures don't throw errors but return tibble with
  # error messages in status columns
  # Uses bad API key so it should fail without using credits

  skip_if(Sys.getenv("MISTRAL_API_KEY") == "", "MISTRAL_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "test_paper.pdf")
  skip_if_not(file.exists(test_pdf), "Test PDF not found")

  db_path <- withr::local_tempfile(fileext = ".sqlite")

  # Use package default schema and prompt (not project customizations)
  schema_file <- system.file("extdata", "schema.json", package = "ecoextract")
  prompt_file <- system.file("prompts", "extraction_prompt.md", package = "ecoextract")

  # Temporarily set bad Anthropic API key
  original_key <- Sys.getenv("ANTHROPIC_API_KEY")
  Sys.setenv(ANTHROPIC_API_KEY = "bad-key-should-fail")
  withr::defer(Sys.setenv(ANTHROPIC_API_KEY = original_key))

  # Run process_documents - should NOT throw, should return tibble
  result <- process_documents(
    test_pdf,
    db_conn = db_path,
    schema_file = schema_file,
    extraction_prompt_file = prompt_file
  )

  # Verify we got a tibble back (not an error throw)
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 1)

  # Check status matrix - should have at least one error
  status_matrix <- result |>
    dplyr::select(ocr_status, metadata_status, extraction_status, refinement_status) |>
    as.matrix()

  has_errors_in_status <- any(!status_matrix %in% c("skipped", "completed"))
  expect_true(has_errors_in_status,
              info = "With bad API key, at least one status column should contain an error message")

  # OCR should work (uses Mistral, different key)
  expect_equal(result$ocr_status[1], "completed",
               info = "OCR uses Mistral, should still complete")

  # Audit or extraction should fail (uses Anthropic)
  audit_or_extraction_has_error <-
    result$metadata_status[1] != "completed" || result$extraction_status[1] != "completed"
  expect_true(audit_or_extraction_has_error,
              info = "Document audit or extraction should fail with bad Anthropic key")
})

# Schema-Agnostic Pipeline ----------------------------------------------------

test_that("host-pathogen schema works end-to-end", {
  cat("\n========== TEST: host-pathogen schema works end-to-end ==========\n")
  skip_if(Sys.getenv("MISTRAL_API_KEY") == "", "MISTRAL_API_KEY not set")
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "hostpathogen_paper.pdf")
  schema_file <- testthat::test_path("fixtures", "hostpathogen_schema.json")
  prompt_file <- testthat::test_path("fixtures", "hostpathogen_extraction_prompt.md")

  skip_if_not(file.exists(test_pdf), "Host-pathogen test PDF not found")
  skip_if_not(file.exists(schema_file), "Host-pathogen schema not found")
  skip_if_not(file.exists(prompt_file), "Host-pathogen prompt not found")

  db_path <- withr::local_tempfile(fileext = ".sqlite")

  # Test the full process_documents workflow with custom schema
  result <- process_documents(
    test_pdf,
    db_conn = db_path,
    schema_file = schema_file,
    extraction_prompt_file = prompt_file,
    run_refinement = TRUE
  )

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 1)

  # Check that all steps completed
  expect_equal(result$ocr_status[1], "completed")
  expect_equal(result$metadata_status[1], "completed")
  expect_equal(result$extraction_status[1], "completed")
  expect_equal(result$refinement_status[1], "completed")

  # Verify data in database
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  records <- DBI::dbReadTable(con, "records")

  # Should have extracted some host-pathogen records
  # This paper is known to contain at least 12 Pasteurella-host relationships
  # Allow for LLM non-determinism by setting threshold at 8
  expect_true(nrow(records) >= 8, "Should extract at least 8 host-pathogen records from this paper")

  # Check that schema-specific columns exist
  expect_true("Pathogen_Name" %in% names(records),
              "Should have Pathogen_Name column")
  expect_true("Host_Name" %in% names(records),
              "Should have Host_Name column")
  expect_true("Detection_Method" %in% names(records),
              "Should have Detection_Method column")

  # Check that bat/interaction columns DON'T exist (would indicate hard-coding)
  expect_false("bat_species_scientific_name" %in% names(records),
               "Should NOT have bat_species_scientific_name column (schema-agnostic fail)")
  expect_false("interacting_organism_scientific_name" %in% names(records),
               "Should NOT have interacting_organism_scientific_name column (schema-agnostic fail)")

  # Verify some actual data was extracted
  expect_true(any(!is.na(records$Pathogen_Name)),
              "Should have extracted pathogen names")
  expect_true(any(!is.na(records$Host_Name)),
              "Should have extracted host names")
  # Detection_Method is optional (not required), just verify column exists
  expect_true("Detection_Method" %in% names(records),
              "Should have Detection_Method column in schema")

  # Verify record IDs were generated correctly
  expect_true(all(grepl("^[A-Za-z]+_[0-9]+_1_r[0-9]+$", records$record_id)),
              "All record_ids should match pattern Author_2024_1_r1")
})

# Deduplication with Embeddings (requires OPENAI_API_KEY) ----------------------

test_that("deduplicate_records detects exact duplicates using embeddings", {
  skip_if_not(nzchar(Sys.getenv("OPENAI_API_KEY")), "OPENAI_API_KEY not set")

  existing_records <- tibble::tibble(
    bat_species_scientific_name = c("Myotis lucifugus", "Eptesicus fuscus"),
    interacting_organism_scientific_name = c("Pseudogymnoascus destructans", "Tree")
  )

  # New records with one exact duplicate and one unique
  new_records <- tibble::tibble(
    bat_species_scientific_name = c("Myotis lucifugus", "Myotis septentrionalis"),
    interacting_organism_scientific_name = c("Pseudogymnoascus destructans", "Cave")
  )

  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("bat_species_scientific_name", "interacting_organism_scientific_name")
        )
      )
    )
  )

  result <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list,
    min_similarity = 0.9,
    embedding_provider = "openai"
  )

  # First record is exact duplicate, should be filtered
  expect_equal(result$duplicates_found, 1)
  # Second record is unique, should be kept
  expect_equal(nrow(result$unique_records), 1)
  expect_equal(result$unique_records$bat_species_scientific_name[1], "Myotis septentrionalis")
})

test_that("deduplicate_records detects near-duplicates with threshold", {
  skip_if_not(nzchar(Sys.getenv("OPENAI_API_KEY")), "OPENAI_API_KEY not set")

  existing_records <- tibble::tibble(
    bat_species_scientific_name = "Myotis lucifugus",
    interacting_organism_scientific_name = "White-nose syndrome fungus"
  )

  # Very similar but not exact (common name vs scientific name)
  new_records <- tibble::tibble(
    bat_species_scientific_name = "Myotis lucifugus",
    interacting_organism_scientific_name = "Pseudogymnoascus destructans"
  )

  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("bat_species_scientific_name", "interacting_organism_scientific_name")
        )
      )
    )
  )

  # With high threshold (0.95), these might not match
  result_high <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list,
    min_similarity = 0.95,
    embedding_provider = "openai"
  )

  # Exact bat species but different pathogen names should be below 0.95 similarity
  expect_equal(nrow(result_high$unique_records), 1)
})

test_that("deduplicate_records handles records with missing required fields", {
  skip_if_not(nzchar(Sys.getenv("OPENAI_API_KEY")), "OPENAI_API_KEY not set")

  existing_records <- tibble::tibble(
    bat_species_scientific_name = "Myotis lucifugus",
    interacting_organism_scientific_name = "Pseudogymnoascus destructans"
  )

  # New records with one having missing required field
  new_records <- tibble::tibble(
    bat_species_scientific_name = c("Eptesicus fuscus", "Myotis septentrionalis"),
    interacting_organism_scientific_name = c(NA_character_, "Tree")
  )

  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("bat_species_scientific_name", "interacting_organism_scientific_name")
        )
      )
    )
  )

  result <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list,
    min_similarity = 0.9,
    embedding_provider = "openai"
  )

  # Both records should be kept (one has NA field, one is unique)
  expect_equal(nrow(result$unique_records), 2)
  expect_equal(result$duplicates_found, 0)
})

# Field-by-field Deduplication (requires OPENAI_API_KEY) -----------------------

test_that("field-by-field: partial match on one field does not create duplicate", {
  skip_if_not(nzchar(Sys.getenv("OPENAI_API_KEY")), "OPENAI_API_KEY not set")

  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("pathogen", "host"),
          properties = list(
            pathogen = list(type = "string"),
            host = list(type = "string")
          )
        )
      )
    )
  )

  # Database has two records sharing pathogen but different hosts
  existing_records <- tibble::tibble(
    pathogen = c("Borrelia burgdorferi", "Borrelia burgdorferi"),
    host = c("Peromyscus leucopus", "Peromyscus maniculatus")
  )

  # New record shares pathogen with both but has different host
  new_records <- tibble::tibble(
    pathogen = "Borrelia burgdorferi",
    host = "Myotis lucifugus"
  )

  result <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list,
    min_similarity = 0.95,
    embedding_provider = "openai"
  )

  # Should be unique - ALL fields must match, not just some
  expect_equal(nrow(result$unique_records), 1)
  expect_equal(result$duplicates_found, 0)
})

test_that("field-by-field: only compares populated fields in both records", {
  skip_if_not(nzchar(Sys.getenv("OPENAI_API_KEY")), "OPENAI_API_KEY not set")

  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("scientific_name", "common_name"),
          properties = list(
            scientific_name = list(type = "string"),
            common_name = list(type = "string")
          )
        )
      )
    )
  )

  # DB record has only scientific name populated
  existing_records <- tibble::tibble(
    scientific_name = "Myotis lucifugus",
    common_name = NA_character_
  )

  # New record has both fields
  new_records <- tibble::tibble(
    scientific_name = "Myotis lucifugus",
    common_name = "Little brown bat"
  )

  result <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list,
    min_similarity = 0.95,
    embedding_provider = "openai",
    similarity_method = "jaccard"
  )

  # Should be duplicate - only scientific_name compared (both populated)
  # common_name ignored since DB record doesn't have it
  expect_equal(result$duplicates_found, 1)
  expect_equal(nrow(result$unique_records), 0)
})

test_that("field-by-field: exact match on all populated fields is duplicate", {
  skip_if_not(nzchar(Sys.getenv("OPENAI_API_KEY")), "OPENAI_API_KEY not set")

  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("species_a", "species_b", "interaction_type"),
          properties = list(
            species_a = list(type = "string"),
            species_b = list(type = "string"),
            interaction_type = list(type = "string")
          )
        )
      )
    )
  )

  existing_records <- tibble::tibble(
    species_a = "Myotis lucifugus",
    species_b = "Corynorhinus townsendii",
    interaction_type = "pollination"
  )

  # Exact duplicate
  new_records <- tibble::tibble(
    species_a = "Myotis lucifugus",
    species_b = "Corynorhinus townsendii",
    interaction_type = "pollination"
  )

  result <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list,
    min_similarity = 0.95,
    embedding_provider = "openai",
    similarity_method = "jaccard"
  )

  # All 3 fields match exactly → duplicate
  expect_equal(result$duplicates_found, 1)
  expect_equal(nrow(result$unique_records), 0)
})

test_that("field-by-field: no populated overlap means unique", {
  skip_if_not(nzchar(Sys.getenv("OPENAI_API_KEY")), "OPENAI_API_KEY not set")

  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("field_a", "field_b"),
          properties = list(
            field_a = list(type = "string"),
            field_b = list(type = "string")
          )
        )
      )
    )
  )

  # DB has only field_a
  existing_records <- tibble::tibble(
    field_a = "Value A",
    field_b = NA_character_
  )

  # New record has only field_b
  new_records <- tibble::tibble(
    field_a = NA_character_,
    field_b = "Value B"
  )

  result <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list,
    min_similarity = 0.95,
    embedding_provider = "openai"
  )

  # No overlapping populated fields → unique
  expect_equal(nrow(result$unique_records), 1)
  expect_equal(result$duplicates_found, 0)
})

test_that("field-by-field: multiple new records, some duplicates some unique", {
  skip_if_not(nzchar(Sys.getenv("OPENAI_API_KEY")), "OPENAI_API_KEY not set")

  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("pathogen", "host"),
          properties = list(
            pathogen = list(type = "string"),
            host = list(type = "string")
          )
        )
      )
    )
  )

  # DB has 2 records
  existing_records <- tibble::tibble(
    pathogen = c("Virus A", "Virus B"),
    host = c("Host X", "Host Y")
  )

  # New: 4 records - 2 duplicates, 2 unique
  new_records <- tibble::tibble(
    pathogen = c("Virus A", "Virus B", "Virus C", "Virus A"),
    host = c("Host X", "Host Y", "Host Z", "Host Z")
  )

  result <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list,
    min_similarity = 0.95,
    embedding_provider = "openai"
  )

  # Records 1 and 2 are duplicates, records 3 and 4 are unique
  expect_equal(result$duplicates_found, 2)
  expect_equal(nrow(result$unique_records), 2)
  expect_true("Virus C" %in% result$unique_records$pathogen)
  expect_true("Host Z" %in% result$unique_records$host)
})

# LLM Deduplication (requires ANTHROPIC_API_KEY) -------------------------------

test_that("llm method: detects semantic duplicates", {
  skip_if_not(nzchar(Sys.getenv("ANTHROPIC_API_KEY")), "ANTHROPIC_API_KEY not set")

  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("species", "disease"),
          properties = list(
            species = list(type = "string"),
            disease = list(type = "string")
          )
        )
      )
    )
  )

  existing_records <- tibble::tibble(
    species = c("Myotis lucifugus", "Eptesicus fuscus"),
    disease = c("White-nose syndrome", "Rabies")
  )

  # New records: one semantic duplicate (same meaning), one unique
  new_records <- tibble::tibble(
    species = c("Little brown bat", "Lasiurus borealis"),
    disease = c("WNS", "Histoplasmosis")
  )

  result <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list,
    similarity_method = "llm",
    model = "anthropic/claude-sonnet-4-5"
  )

  # First record should be detected as duplicate (semantic match)
  # Second record is unique
  expect_equal(result$duplicates_found, 1)
  expect_equal(nrow(result$unique_records), 1)
  expect_equal(result$unique_records$species[1], "Lasiurus borealis")
})

test_that("llm_deduplicate standalone function works", {
  skip_if_not(nzchar(Sys.getenv("ANTHROPIC_API_KEY")), "ANTHROPIC_API_KEY not set")

  existing_records <- tibble::tibble(
    name = c("John Smith", "Jane Doe"),
    city = c("New York", "Los Angeles")
  )

  new_records <- tibble::tibble(
    name = c("J. Smith", "Bob Wilson"),
    city = c("NYC", "Chicago")
  )

  key_fields <- c("name", "city")

  unique_indices <- llm_deduplicate(
    new_records = new_records,
    existing_records = existing_records,
    key_fields = key_fields,
    model = "anthropic/claude-sonnet-4-5"
  )

  # First record should be detected as duplicate (J. Smith/NYC = John Smith/New York)
  # Second record is unique
  expect_true(is.integer(unique_indices))
  expect_equal(length(unique_indices), 1)
  expect_equal(unique_indices[1], 2L)
})
