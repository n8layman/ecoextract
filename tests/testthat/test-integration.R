# Integration Tests
# Test that API calls return valid structure (not content accuracy)

test_that("extract_records returns valid structure", {
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

test_that("refine_records returns valid structure", {
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

test_that("perform_ocr_audit returns valid structure", {
  skip_if_not(has_api_keys(), "API keys not available")

  ocr_content <- sample_ocr_content()

  result <- perform_ocr_audit(ocr_content)

  # Check structure
  expect_type(result, "list")
  expect_true("audited_markdown" %in% names(result))
  expect_type(result$audited_markdown, "character")
})
