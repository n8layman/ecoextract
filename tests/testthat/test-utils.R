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

test_that("from_project_relative_path resolves stored paths from a subdirectory", {
  project <- withr::local_tempdir()
  file.create(file.path(project, "DESCRIPTION"))
  dir.create(file.path(project, "pdfs"))
  dir.create(file.path(project, "analysis"))
  pdf <- file.path(project, "pdfs", "paper.pdf")
  file.create(pdf)

  stored <- to_project_relative_path(pdf)
  expect_equal(stored, "pdfs/paper.pdf")

  withr::local_dir(file.path(project, "analysis"))
  expect_true(file.exists(from_project_relative_path(stored)))
  expect_equal(from_project_relative_path("/abs/paper.pdf"), "/abs/paper.pdf")
})

#' Replace ellmer::chat() with a fake whose first structured call fails
#' with `first_error` and whose second returns list(answer = "ok")
local_fake_chat <- function(first_error, env = parent.frame()) {
  calls <- new.env()
  calls$n <- 0
  local_mocked_bindings(
    chat = function(...) {
      fake <- new.env()
      fake$turns <- list()
      fake$chat_structured <- function(...) {
        calls$n <- calls$n + 1
        if (calls$n == 1) stop(first_error)
        fake$turns <- list(
          ellmer::UserTurn(list(ellmer::ContentText("input"))),
          ellmer::AssistantTurn(list(ellmer::ContentText("{}")), tokens = c(10, 5, 0))
        )
        list(answer = "ok")
      }
      fake$get_turns <- function() fake$turns
      fake$get_tokens <- function() {
        chat <- ellmer::chat_anthropic(credentials = function() "unused")
        chat$set_turns(fake$turns)
        chat$get_tokens()
      }
      fake
    },
    .package = "ellmer",
    .env = env
  )
  calls
}

test_that("try_models_with_fallback retries the same model after a transient failure", {
  withr::local_envvar(ANTHROPIC_API_KEY = "unused")
  schema <- ellmer::TypeJsonSchema(
    description = "Test schema",
    json = list(type = "object", properties = list(answer = list(type = "string")))
  )

  # jsonlite's messages for stray markup after the object and for an
  # unescaped quote inside a string, and an HTTP 500 server error
  for (first_error in c("parse error: trailing garbage",
                        "lexical error: invalid char in json text.",
                        "HTTP 500 Internal Server Error.")) {
    calls <- local_fake_chat(first_error)

    result <- try_models_with_fallback(
      models = "anthropic/claude-sonnet-5",
      system_prompt = "system",
      context = "input",
      schema = schema
    )

    expect_equal(calls$n, 2)
    expect_equal(result$result$answer, "ok")
    expect_match(result$error_log, strsplit(first_error, ":")[[1]][1])
  }
})

test_that("llm_params and llm_api_args turn thinking off unless an effort is set", {
  claude <- "anthropic/claude-sonnet-5"
  gemini <- "google_gemini/gemini-2.5-flash"
  openai <- "openai/gpt-4.1"

  # Thinking off by default: Claude through the request body, Gemini through params
  expect_equal(llm_api_args(claude), list(thinking = list(type = "disabled")))
  expect_null(llm_params(claude, 1000)$reasoning_effort)
  expect_equal(llm_params(gemini, 1000)$reasoning_tokens, 0)
  expect_equal(llm_api_args(gemini), list())
  expect_equal(llm_api_args(openai), list())

  # An effort level turns thinking on for every provider
  for (model in c(claude, gemini, openai)) {
    expect_equal(llm_params(model, 1000, "low")$reasoning_effort, "low")
    expect_null(llm_params(model, 1000, "low")$reasoning_tokens)
    expect_equal(llm_api_args(model, "low"), list())
  }
  expect_equal(llm_params(claude, 1000)$max_tokens, 1000)
})

test_that("try_models_with_fallback passes thinking settings to ellmer::chat", {
  withr::local_envvar(ANTHROPIC_API_KEY = "unused")
  captured <- new.env()
  local_mocked_bindings(
    chat = function(name, ..., params = NULL, api_args = NULL) {
      captured$params <- params
      captured$api_args <- api_args
      fake <- new.env()
      fake$chat_structured <- function(...) list(answer = "ok")
      fake$get_turns <- function() list()
      fake$get_tokens <- function() {
        ellmer::chat_anthropic(credentials = function() "unused")$get_tokens()
      }
      fake
    },
    .package = "ellmer"
  )
  schema <- ellmer::TypeJsonSchema(
    description = "Test schema",
    json = list(type = "object", properties = list(answer = list(type = "string")))
  )

  try_models_with_fallback("anthropic/claude-sonnet-5", "system", "input", schema)
  expect_equal(captured$api_args, list(thinking = list(type = "disabled")))

  try_models_with_fallback("anthropic/claude-sonnet-5", "system", "input", schema,
                           reasoning_effort = "high")
  expect_equal(captured$params$reasoning_effort, "high")
  expect_equal(captured$api_args, list())
})

test_that("try_models_with_fallback does not retry client errors", {
  withr::local_envvar(ANTHROPIC_API_KEY = "unused")
  schema <- ellmer::TypeJsonSchema(
    description = "Test schema",
    json = list(type = "object", properties = list(answer = list(type = "string")))
  )
  calls <- local_fake_chat("HTTP 400 Bad Request.")

  expect_error(
    try_models_with_fallback("anthropic/claude-sonnet-5", "system", "input", schema),
    "HTTP 400"
  )
  expect_equal(calls$n, 1)
})
