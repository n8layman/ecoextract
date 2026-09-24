# Utility Tests
# Tests for ID generation and helper functions

# ID Generation ----------------------------------------------------------------

test_that("generate_record_id creates correct format", {
  id <- generate_record_id(build_record_id_prefix(list("Smith", 2020L)), 1)

  expect_type(id, "character")
  expect_equal(id, "Smith_2020_1_r1")
})

test_that("generate_record_id numbers a vector of sequence numbers", {
  ids <- generate_record_id("Smith_2020_1", 3:5)

  expect_equal(ids, c("Smith_2020_1_r3", "Smith_2020_1_r4", "Smith_2020_1_r5"))
})

test_that("build_record_id_prefix strips non-alphanumeric characters", {
  expect_equal(build_record_id_prefix(list("O'Brien", 2020L)), "OBrien_2020_1")
  expect_equal(build_record_id_prefix(list("2024-001234")), "2024001234_1")
})

test_that("build_record_id_prefix uses Unknown for missing values", {
  expect_equal(build_record_id_prefix(list(NA, 2020L)), "Unknown_2020_1")
  expect_equal(build_record_id_prefix(list("Smith", NULL)), "Smith_Unknown_1")
  expect_equal(build_record_id_prefix(list("--")), "Unknown_1")
})

# Schema Cleaning --------------------------------------------------------------

nested_object_schema <- function() {
  list(
    type = "object",
    additionalProperties = TRUE,
    properties = list(
      items = list(
        type = "array",
        items = list(type = "object", properties = list(a = list(type = "string")))
      ),
      nullable_obj = list(type = list("object", "null"), properties = list())
    )
  )
}

test_that("clean_schema_for_api sets additionalProperties false on every object", {
  schema <- ellmer::TypeJsonSchema(description = "test", json = nested_object_schema())

  json <- clean_schema_for_api(schema)@json

  expect_false(json$additionalProperties)
  expect_false(json$properties$items$items$additionalProperties)
  expect_false(json$properties$nullable_obj$additionalProperties)
  expect_null(json$properties$items$additionalProperties)
})

test_that("clean_schema_for_api removes additionalProperties for Gemini", {
  schema <- ellmer::TypeJsonSchema(description = "test", json = nested_object_schema())

  json <- clean_schema_for_api(schema, gemini = TRUE)@json

  expect_null(json$additionalProperties)
  expect_null(json$properties$items$items$additionalProperties)
})

test_that("add_record_id_to_schema declares record_id as a required record field", {
  schema_list <- jsonlite::fromJSON(
    load_config_file(NULL, "schema.json", "extdata"),
    simplifyVector = FALSE
  )
  original_fields <- names(schema_list$properties$records$items$properties)

  items <- add_record_id_to_schema(schema_list)$properties$records$items

  expect_equal(items$properties$record_id$type, "string")
  expect_true("record_id" %in% unlist(items$required))
  expect_true(all(original_fields %in% names(items$properties)))
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

test_that("chat_usage sums tokens across assistant turns", {
  chat <- ellmer::chat_anthropic(credentials = function() "unused")
  chat$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText("first"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("reply")), tokens = c(100, 20, 5)),
    ellmer::UserTurn(list(ellmer::ContentText("second"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("reply")), tokens = c(150, 30, 0))
  ))

  expect_equal(
    chat_usage(chat),
    list(input_tokens = 250, output_tokens = 50, cached_input_tokens = 5)
  )
})

test_that("chat_usage returns zeros for a chat with no turns", {
  chat <- ellmer::chat_anthropic(credentials = function() "unused")
  expect_equal(
    chat_usage(chat),
    list(input_tokens = 0, output_tokens = 0, cached_input_tokens = 0)
  )
})

test_that("add_usage sums element-wise and treats NULL as no call", {
  x <- list(input_tokens = 10, output_tokens = 2, cached_input_tokens = 1)
  y <- list(input_tokens = 5, output_tokens = 3, cached_input_tokens = 0)

  expect_equal(
    add_usage(x, y),
    list(input_tokens = 15, output_tokens = 5, cached_input_tokens = 1)
  )
  expect_equal(add_usage(NULL, y), y)
  expect_equal(add_usage(x, NULL), x)
  expect_null(add_usage(NULL, NULL))
})
