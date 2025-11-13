# Schema-Agnostic Tests
# Tests that the package works with completely different domains (not bat interactions)
# This ensures no hard-coded assumptions about "bats" or "interactions"

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
    extraction_prompt_file = prompt_file
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
  expect_true(any(!is.na(records$Detection_Method)),
              "Should have extracted detection methods")

  # Verify record IDs were generated correctly
  expect_true(all(grepl("^[A-Za-z]+[0-9]+-o[0-9]+$", records$record_id)),
              "All record_ids should match pattern Author2024-o1")
})
