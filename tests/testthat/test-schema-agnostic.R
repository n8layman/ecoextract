# Schema-Agnostic Tests
# Tests that the package works with completely different domains (not bat interactions)
# This ensures no hard-coded assumptions about "bats" or "interactions"

test_that("pollination schema works end-to-end", {
  cat("\n========== TEST: pollination schema works end-to-end ==========\n")
  skip_if(Sys.getenv("MISTRAL_API_KEY") == "", "MISTRAL_API_KEY not set")
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "", "ANTHROPIC_API_KEY not set")

  test_pdf <- testthat::test_path("fixtures", "pollination_paper.pdf")
  schema_file <- testthat::test_path("fixtures", "pollination_schema.json")
  prompt_file <- testthat::test_path("fixtures", "pollination_extraction_prompt.md")

  skip_if_not(file.exists(test_pdf), "Pollination test PDF not found")
  skip_if_not(file.exists(schema_file), "Pollination schema not found")
  skip_if_not(file.exists(prompt_file), "Pollination prompt not found")

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
  expect_equal(result$audit_status[1], "completed")
  expect_equal(result$extraction_status[1], "completed")
  expect_equal(result$refinement_status[1], "completed")

  # Verify data in database
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  records <- DBI::dbReadTable(con, "records")

  # Should have extracted some pollination records
  expect_true(nrow(records) > 0, "Should extract at least one pollination record")

  # Check that schema-specific columns exist
  expect_true("plant_species_scientific_name" %in% names(records),
              "Should have plant_species_scientific_name column")
  expect_true("pollinator_species_scientific_name" %in% names(records),
              "Should have pollinator_species_scientific_name column")
  expect_true("pollinator_type" %in% names(records),
              "Should have pollinator_type column")

  # Check that bat/interaction columns DON'T exist (would indicate hard-coding)
  expect_false("bat_species_scientific_name" %in% names(records),
               "Should NOT have bat_species_scientific_name column (schema-agnostic fail)")
  expect_false("interacting_organism_scientific_name" %in% names(records),
               "Should NOT have interacting_organism_scientific_name column (schema-agnostic fail)")

  # Verify some actual data was extracted
  expect_true(any(!is.na(records$plant_species_scientific_name)),
              "Should have extracted plant species names")
  expect_true(any(!is.na(records$pollinator_species_scientific_name)),
              "Should have extracted pollinator species names")

  # Verify occurrence IDs were generated correctly
  expect_true(all(grepl("^[A-Za-z]+[0-9]+-o[0-9]+$", records$occurrence_id)),
              "All occurrence_ids should match pattern Author2024-o1")
})
