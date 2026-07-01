# Utility Tests
# Tests for ID generation and helper functions

# ID Generation ----------------------------------------------------------------

test_that("generate_record_id creates correct format", {
  id <- generate_record_id("Smith", 2020, 1)

  expect_type(id, "character")
  expect_match(id, "Smith_2020_1_r1")
})

test_that("generate_record_id handles special characters", {
  id <- generate_record_id("O'Brien", 2020, 1)

  expect_match(id, "OBrien_2020_1_r1")
})

test_that("add_record_ids adds IDs to all rows", {
  records <- sample_records()
  records$record_id <- NULL

  result <- add_record_ids(records, "Test", 2020)

  expect_true("record_id" %in% names(result))
  expect_equal(nrow(result), nrow(records))
  expect_true(all(!is.na(result$record_id)))
})

test_that("generate_uuid produces valid UUID v4", {
  uuid <- generate_uuid()

  expect_type(uuid, "character")
  expect_equal(nchar(uuid), 36L)
  expect_match(uuid, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
})

test_that("generate_uuid produces unique values", {
  uuids <- vapply(seq_len(100L), function(i) generate_uuid(), character(1))
  expect_equal(length(unique(uuids)), 100L)
})

# Utilities --------------------------------------------------------------------

test_that("estimate_tokens handles various inputs", {
  expect_equal(estimate_tokens(NULL), 0)
  expect_equal(estimate_tokens(""), 0)
  expect_equal(estimate_tokens(NA_character_), 0)

  text <- "This is a test string"
  tokens <- estimate_tokens(text)
  expect_type(tokens, "double")
  expect_true(tokens > 0)
})
