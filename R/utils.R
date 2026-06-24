#' Internal utility functions

#' Find project root by walking up from a directory
#'
#' Walks up the directory tree from \code{start_dir} until a project marker
#' (\code{.git}, \code{.Rproj}, \code{DESCRIPTION}, \code{.here}) is found.
#' Returns \code{NULL} if no marker is found before the filesystem root —
#' this happens when the PDF lives outside any recognised project (e.g. a
#' one-off download or a network path). In that case callers fall back to
#' storing an absolute path, which is machine-specific and will break if the
#' database is shared or the folder is moved.
#' @keywords internal
find_project_root <- function(start_dir) {
  markers <- c(".git", ".Rproj", "DESCRIPTION", ".here")
  dir <- normalizePath(start_dir, winslash = "/", mustWork = FALSE)
  repeat {
    if (any(file.exists(file.path(dir, markers)))) return(dir)
    parent <- normalizePath(dirname(dir), winslash = "/", mustWork = FALSE)
    if (parent == dir) return(NULL)
    dir <- parent
  }
}

#' Convert a file path to project-relative form for database storage
#'
#' Uses \code{find_project_root()} starting from the file's own directory, so
#' the root is always anchored to the PDF project — not the \code{.db} location
#' or the working directory. Falls back to an absolute path when no project
#' root is found.
#' @keywords internal
to_project_relative_path <- function(file_path) {
  abs_path <- normalizePath(file_path, winslash = "/", mustWork = FALSE)
  root <- find_project_root(dirname(abs_path))
  if (is.null(root)) return(abs_path)
  root_prefix <- paste0(root, "/")
  if (!startsWith(abs_path, root_prefix)) return(abs_path)
  substring(abs_path, nchar(root_prefix) + 1)
}

#' Create record IDs for a batch of records (internal)
#' @param interactions Dataframe of records
#' @param author_lastname Author lastname for ID generation
#' @param publication_year Publication year for ID generation
#' @return Dataframe with record_id column added
#' @keywords internal
add_record_ids <- function(interactions, author_lastname, publication_year, offset = 0L) {
  if (nrow(interactions) == 0) {
    return(interactions)
  }

  # Generate sequential record IDs, starting after offset to avoid collisions
  interactions$record_id <- sapply(1:nrow(interactions), function(i) {
    generate_record_id(author_lastname, publication_year, offset + i)
  })

  return(interactions)
}

#' Simple logging function
#' @param message Message to log
#' @param level Log level (INFO, WARNING, ERROR)
#' @keywords internal
log_message <- function(message, level = "INFO") {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat("[", timestamp, "] ", level, ": ", message, "\n", sep = "")
}

estimate_tokens <- function(text) {
  # Handle NULL input
  if (is.null(text)) {
    return(0)
  }

  # Convert to JSON if not already a character
  if (!is.character(text)) {
    tryCatch({
      text <- jsonlite::toJSON(text, auto_unbox = TRUE)
    }, error = function(e) {
      # If JSON conversion fails, try deparse then as.character as fallback
      tryCatch({
        text <- paste(deparse(text), collapse = " ")
      }, error = function(e2) {
        # Ultimate fallback for unconvertible objects
        text <- "unknown"
      })
    })
  }

  # Handle NA or empty string after conversion
  if (length(text) == 0 || is.na(text) || text == "") {
    return(0)
  }

  ceiling(nchar(text) / 4)
}

#' Build existing records context for LLM prompts
#' @param existing_records Dataframe of existing records
#' @param document_id Optional document ID for context
#' @param include_record_id Whether to include record_id (TRUE for refinement, FALSE for extraction)
#' @return Character string with existing records formatted for LLM context
#' @keywords internal
build_existing_records_context <- function(existing_records, document_id = NULL, include_record_id = FALSE) {
  if (is.null(existing_records) || !is.data.frame(existing_records) || nrow(existing_records) == 0) {
    return("")  # Return empty string, context header handles the messaging
  }

  # Filter out deleted records - they should not be shown to extraction/refinement
  # deleted_by_user is TEXT: NA means not deleted, timestamp means deleted
  if ("deleted_by_user" %in% names(existing_records)) {
    existing_records <- existing_records[is.na(existing_records$deleted_by_user), ]
  }

  # Recheck if any records remain after filtering
  if (nrow(existing_records) == 0) {
    return("")  # Return empty string
  }

  # Exclude metadata columns from display
  # record_id: show during refinement (so LLM preserves it), hide during extraction (LLM doesn't generate it)
  metadata_cols <- c("document_id", "extraction_timestamp",
                     "prompt_hash",
                     "human_edited", "deleted_by_user", "fields_changed_count")

  # Add record_id to metadata_cols if we don't want to show it (extraction)
  if (!include_record_id) {
    metadata_cols <- c(metadata_cols, "record_id")
  }

  data_cols <- setdiff(names(existing_records), metadata_cols)

  # Build context as simple JSON representation
  context_lines <- c("Existing records:", "")

  for (i in seq_len(nrow(existing_records))) {
    row <- existing_records[i, data_cols, drop = FALSE]

    # Convert row to simple key-value format
    record_parts <- character(0)
    for (col in data_cols) {
      val <- row[[col]]

      # Convert lists to JSON strings
      if (is.list(val)) {
        val <- jsonlite::toJSON(val, auto_unbox = TRUE)
      }

      # Include value if it's not NA and not empty
      # Need to check for length > 0 first to avoid issues with lists/vectors
      if (length(val) > 0 && !all(is.na(val))) {
        val_str <- as.character(val)
        if (nchar(val_str) > 0 && val_str != "") {
          # Truncate very long values (like supporting_source_sentences)
          if (nchar(val_str) > 100) {
            val_str <- paste0(substr(val_str, 1, 97), "...")
          }
          record_parts <- c(record_parts, paste0(col, ": ", val_str))
        }
      }
    }

    context_line <- paste0("- ", paste(record_parts, collapse = ", "))
    context_lines <- c(context_lines, context_line)
  }

  return(paste(context_lines, collapse = "\n"))
}

#' Strip non-standard JSON Schema properties recursively
#'
#' Removes properties that waste tokens and some providers reject:
#' additionalProperties, $schema, _comment, and x-* extensions.
#'
#' @param x List representing a JSON schema
#' @return List with non-standard properties removed
#' @keywords internal
strip_non_standard_schema_properties <- function(x) {
  if (is.list(x)) {
    x[["additionalProperties"]] <- NULL
    x[["$schema"]] <- NULL
    x[["_comment"]] <- NULL
    x_names <- grep("^x-", names(x), value = TRUE)
    for (nm in x_names) x[[nm]] <- NULL
    x <- lapply(x, strip_non_standard_schema_properties)
  }
  x
}

#' Convert nullable type arrays to Gemini's nullable format
#'
#' JSON Schema uses \code{"type": ["string", "null"]} for nullable fields.
#' Gemini requires \code{"type": "string", "nullable": true} instead.
#'
#' @param x List representing a JSON schema
#' @return List with nullable types converted
#' @keywords internal
convert_nullable_for_gemini <- function(x) {
  if (is.list(x)) {
    type_val <- x[["type"]]
    if (!is.null(type_val) && length(type_val) > 1) {
      types <- unlist(type_val)
      if ("null" %in% types) {
        non_null <- setdiff(types, "null")
        x[["type"]] <- if (length(non_null) == 1) non_null else non_null
        x[["nullable"]] <- TRUE
      }
    }
    x <- lapply(x, convert_nullable_for_gemini)
  }
  x
}

#' Clean a TypeJsonSchema for API use
#'
#' Strips non-standard properties. For Gemini, also converts nullable types.
#'
#' @param schema An ellmer TypeJsonSchema object
#' @param gemini Logical. If TRUE, also convert nullable type arrays.
#' @return A new TypeJsonSchema with properties cleaned
#' @keywords internal
clean_schema_for_api <- function(schema, gemini = FALSE) {
  # Only process TypeJsonSchema (extraction/refinement schemas).
  # Native TypeObject (metadata) is handled directly by ellmer.
  json <- tryCatch(schema@json, error = function(e) NULL)
  if (is.null(json)) return(schema)
  json <- strip_non_standard_schema_properties(json)
  if (gemini) json <- convert_nullable_for_gemini(json)
  ellmer::TypeJsonSchema(description = schema@description, json = json)
}

#' Parse a JSON string, fixing mismatched Unicode quotation marks
#'
#' When LLMs generate JSON containing text with paired Unicode quotes
#' (e.g. Bulgarian double low-9 / left double quotes), they sometimes use ASCII " (U+0022)
#' as the closing quote instead of the proper Unicode character, breaking
#' JSON parsing. This function tries normal parsing first, then fixes
#' the common pattern before retrying.
#'
#' @param json_str Character string containing JSON
#' @return Parsed list
#' @keywords internal
parse_json_with_quote_fix <- function(json_str) {
  result <- tryCatch(
    jsonlite::fromJSON(json_str, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.null(result)) return(result)

  # Fix: U+201E (double low-9 quote) paired with ASCII " instead of U+201C.
  # The model copies e.g. \u201EKhristo G. Danev" from OCR text, where the
  # closing " is ASCII U+0022, prematurely terminating the JSON string.
  open_quote <- intToUtf8(0x201E)
  close_quote <- intToUtf8(0x201C)
  pattern <- paste0(open_quote, '([^"]{1,500})"')
  replacement <- paste0(open_quote, "\\1", close_quote)
  fixed <- gsub(pattern, replacement, json_str, perl = TRUE)
  jsonlite::fromJSON(fixed, simplifyVector = FALSE)
}

#' Normalize raw structured output from chat_structured(convert = FALSE)
#'
#' When using \code{convert = FALSE}, the raw result may be a parsed list
#' (TypeObject without envelope), a list with a \code{data} string element
#' (data-string envelope), or a bare character string. This function
#' normalizes all cases to a parsed list.
#'
#' @param raw Raw result from chat_structured(convert = FALSE)
#' @return Parsed list
#' @keywords internal
normalize_structured_result <- function(raw) {
  # Already a usable list (TypeObject without envelope)
  if (is.list(raw) && !("data" %in% names(raw) && is.character(raw$data))) {
    return(raw)
  }
  # Data-string envelope or bare string: unwrap and parse
  json_str <- if (is.character(raw)) raw else raw$data
  parse_json_with_quote_fix(json_str)
}

#' Detect whether an LLM error is a content refusal
#'
#' When a model refuses content (e.g. papers about select agents), it may
#' truncate structured output early rather than returning an explicit refusal
#' signal. This produces parse errors indistinguishable from network issues.
#' This function checks for refusal indicators in the error and response.
#'
#' @param error_msg The error message string
#' @param raw_content Raw response content from the API (may be NULL)
#' @param stop_reason The stop_reason from the API response (may be NULL)
#' @return Logical
#' @keywords internal
is_content_refusal <- function(error_msg, raw_content = NULL, stop_reason = NULL) {
  # Explicit refusal signal

  if (!is.null(stop_reason) && stop_reason == "refusal") return(TRUE)

  # Parse error with minimal content suggests truncated refusal
  is_parse_error <- grepl("premature EOF|parse error|lexical error", error_msg)
  if (is_parse_error && !is.null(raw_content)) {
    content_str <- tryCatch(
      paste(unlist(raw_content), collapse = " "),
      error = function(e) ""
    )
    # Refusal language in truncated output
    refusal_patterns <- paste(
      "I cannot", "I'm unable", "I can't", "content policy",
      "I'm not able", "unable to process", "cannot assist",
      sep = "|"
    )
    if (grepl(refusal_patterns, content_str, ignore.case = TRUE)) return(TRUE)

    # Very short structured output (model started JSON then stopped)
    if (nchar(content_str) < 200 && nchar(content_str) > 0) return(TRUE)
  }

  FALSE
}

#' Check that API keys exist for specified models
#'
#' @param models Character vector of model names
#' @return NULL (stops with error if keys missing)
#' @keywords internal
check_api_keys_for_models <- function(models) {
  # Map provider prefixes to environment variable names
  provider_keys <- list(
    "anthropic" = "ANTHROPIC_API_KEY",
    "openai" = "OPENAI_API_KEY",
    "mistral" = "MISTRAL_API_KEY",
    "groq" = "GROQ_API_KEY",
    "google_gemini" = "GOOGLE_API_KEY"
  )

  # Extract unique providers from model list
  providers <- unique(sapply(strsplit(models, "/"), `[`, 1))

  # Check each provider
  missing_keys <- character(0)
  for (provider in providers) {
    key_name <- provider_keys[[provider]]
    if (is.null(key_name)) {
      # Unknown provider - skip check (ellmer might handle it)
      next
    }

    # Check if environment variable exists and is not empty
    key_value <- Sys.getenv(key_name, unset = NA)
    if (is.na(key_value) || nchar(key_value) == 0) {
      missing_keys <- c(missing_keys, key_name)
    }
  }

  # Stop with informative error if any keys are missing
  if (length(missing_keys) > 0) {
    stop(
      "Missing API keys for the following providers:\n",
      paste0("  - ", missing_keys, collapse = "\n"), "\n\n",
      "Please set the following environment variables:\n",
      paste0("  ", missing_keys, " = <your-api-key>", collapse = "\n"), "\n\n",
      "You can set them in your .Renviron file or use Sys.setenv()\n",
      "Models requested: ", paste(models, collapse = ", ")
    )
  }
}

#' Try multiple LLM models with fallback on refusal
#'
#' Attempts to get structured output from LLMs in sequential order.
#' If a model refuses (stop_reason == "refusal") or errors, tries the next model.
#'
#' When \code{reasoning_prompt} is provided, a two-turn conversation is used:
#' turn 1 returns structured reasoning (always captured), turn 2 uses that
#' reasoning as context and returns the structured records. Both turns share
#' the same chat object so turn 1 reasoning is in context for turn 2.
#' On any failure, both turns are retried together with the next model.
#'
#' @param models Character vector of model names (e.g., c("anthropic/claude-sonnet-4-5", "mistral/mistral-large-latest"))
#' @param system_prompt System prompt for the LLM
#' @param context User context/input for the LLM (turn 1 message)
#' @param schema ellmer type schema for structured output (turn 2 in two-turn mode)
#' @param max_tokens Maximum tokens for response (default 64000)
#' @param max_retries Maximum retry attempts per model for stochastic failures (default 2)
#' @param step_name Name of the step for logging (default "LLM call")
#' @param reasoning_prompt When non-NULL, enables two-turn mode. This string is
#'   the turn 2 user message instructing the model to extract after reasoning.
#'   The turn 1 result (reasoning) and turn 2 result (records) are combined into
#'   a single list returned as \code{result}.
#' @return List with result (structured output), model_used (which model succeeded), and error_log (JSON string of failed attempts)
#' @keywords internal
try_models_with_fallback <- function(
  models,
  system_prompt,
  context,
  schema,
  max_tokens = 64000,
  max_retries = 2,
  step_name = "LLM call",
  reasoning_prompt = NULL
) {
  # Ensure models is a character vector
  if (!is.character(models) || length(models) == 0) {
    stop("models must be a non-empty character vector")
  }

  # Check that API keys exist for all models in the list
  check_api_keys_for_models(models)

  errors <- list()

  for (model in models) {
    for (attempt in seq_len(max_retries)) {
    tryCatch({
      if (attempt > 1) message(sprintf("  Retry %d/%d for %s", attempt, max_retries, model))
      # Create chat instance
      is_gemini <- startsWith(model, "google_gemini/")
      chat <- ellmer::chat(
        name = model,
        system_prompt = system_prompt,
        echo = "none",
        params = if (is_gemini) {
          # Disable Gemini thinking to avoid truncating structured output.
          ellmer::params(max_tokens = max_tokens, reasoning_tokens = 0)
        } else {
          list(max_tokens = max_tokens)
        }
      )

      # Strip non-standard JSON Schema properties ($schema, x-*, _comment,
      # additionalProperties) that waste tokens and some providers reject.
      # For Gemini, also convert nullable type arrays to nullable format.
      # Native TypeObject (metadata) passes through unchanged.
      model_schema <- clean_schema_for_api(schema, gemini = is_gemini)

      if (!is.null(reasoning_prompt)) {
        # Two-turn mode: turn 1 captures reasoning, turn 2 extracts records.
        # Both turns share the same chat object so reasoning is in context for turn 2.
        reasoning_schema_obj <- ellmer::TypeJsonSchema(
          description = "Document analysis schema",
          json = list(
            type = "object",
            properties = list(
              reasoning = list(
                type = "string",
                description = "Step-by-step analysis of the document: structure, potential interactions, organism identifiability, and extraction decisions"
              )
            ),
            required = list("reasoning")
          )
        )
        reasoning_schema_clean <- clean_schema_for_api(reasoning_schema_obj, gemini = is_gemini)

        # Turn 1: reasoning
        raw1 <- chat$chat_structured(context, type = reasoning_schema_clean, convert = FALSE)
        turn1 <- normalize_structured_result(raw1)

        # Check for refusal on turn 1 before evaluating reasoning content.
        # A refusal produces empty/truncated output — detecting it here ensures
        # it's logged as a content refusal rather than a retryable stochastic failure.
        turns_after_1 <- chat$get_turns()
        if (length(turns_after_1) > 0) {
          last_turn_1 <- turns_after_1[[length(turns_after_1)]]
          t1_stop_reason <- last_turn_1@json$stop_reason
          t1_raw_content <- last_turn_1@json$content
          if (!is.null(t1_stop_reason) && t1_stop_reason == "refusal") {
            stop("Model refused request (stop_reason: refusal)")
          }
          if (is.null(turn1$reasoning) || nchar(turn1$reasoning) == 0) {
            if (is_content_refusal("", t1_raw_content, t1_stop_reason)) {
              stop("Model refused request (stop_reason: refusal)")
            }
            stop("Model returned empty/missing reasoning (schema requires it)")
          }
        } else if (is.null(turn1$reasoning) || nchar(turn1$reasoning) == 0) {
          stop("Model returned empty/missing reasoning (schema requires it)")
        }

        # Turn 2: structured records, with turn 1 reasoning in context
        raw2 <- chat$chat_structured(reasoning_prompt, type = model_schema, convert = FALSE)
        turn2 <- normalize_structured_result(raw2)

        # Log result structure for diagnostics
        result_names <- paste(c(names(turn1), names(turn2)), collapse = ", ")
        message(sprintf("  Raw result structure: %s", result_names))

        # Check refusal on final turn
        turns <- chat$get_turns()
        if (length(turns) > 0) {
          last_turn <- turns[[length(turns)]]
          if (!is.null(last_turn@json$stop_reason) && last_turn@json$stop_reason == "refusal") {
            stop("Model refused request (stop_reason: refusal)")
          }
        }

        # Combine turn 1 reasoning and turn 2 records into a single result
        result <- c(turn1, turn2)

      } else {
        # Single-turn mode (metadata, refinement, and any non-extraction callers)
        raw <- chat$chat_structured(context, type = model_schema, convert = FALSE)
        result <- normalize_structured_result(raw)

        # Log raw result structure for diagnostics
        result_names <- if (is.list(result)) paste(names(result), collapse = ", ") else class(result)
        message(sprintf("  Raw result structure: %s", result_names))

        # Check if model refused despite returning structured output
        turns <- chat$get_turns()
        if (length(turns) > 0) {
          last_turn <- turns[[length(turns)]]
          if (!is.null(last_turn@json$stop_reason) && last_turn@json$stop_reason == "refusal") {
            stop("Model refused request (stop_reason: refusal)")
          }
        }

        # Validate reasoning field if schema requires it.
        # ellmer may drop NULL fields from structured output, so check
        # both presence and content.
        has_reasoning <- is.list(result) && "reasoning" %in% names(result)
        reasoning_empty <- !has_reasoning ||
          is.null(result$reasoning) ||
          (is.character(result$reasoning) && nchar(result$reasoning) == 0)

        if (reasoning_empty) {
          schema_json <- tryCatch(schema@json, error = function(e) NULL)
          schema_requires_reasoning <- !is.null(schema_json) &&
            "reasoning" %in% schema_json$required
          if (schema_requires_reasoning) {
            stop("Model returned empty/missing reasoning (schema requires it)")
          }
        }
      }

      # Success - return immediately with error log
      message(sprintf("%s completed successfully using %s", step_name, model))

      # Convert error log to JSON (NULL if no errors)
      error_log_json <- if (length(errors) > 0) {
        jsonlite::toJSON(errors, auto_unbox = TRUE)
      } else {
        NA_character_
      }

      return(list(
        result = result,
        model_used = model,
        error_log = error_log_json
      ))

    }, error = function(e) {
      # Capture raw response from model
      raw_content <- NULL
      stop_reason <- NULL
      tryCatch({
        turns <- chat$get_turns()
        if (length(turns) > 0) {
          last_turn <- turns[[length(turns)]]
          raw_content <- last_turn@json$content
          stop_reason <- last_turn@json$stop_reason
        }
      }, error = function(e2) {})

      msg <- conditionMessage(e)

      # Detect content refusals disguised as parse errors.
      # When a model refuses content (e.g. select agents), it truncates
      # the structured output early, causing a parse error. Distinguish
      # this from genuine network/API failures for clearer logging.
      is_refusal <- is_content_refusal(msg, raw_content, stop_reason)
      if (is_refusal) {
        message(sprintf("%s refused by %s (content policy), falling back...",
                        step_name, model))
      } else {
        message(sprintf("%s failed with %s: %s", step_name, model, msg))
      }

      # Store for audit log (use <<- to modify parent scope)
      errors[[model]] <<- list(
        error = if (is_refusal) paste("Content refusal:", msg) else msg,
        content = raw_content,
        stop_reason = stop_reason,
        refusal = is_refusal,
        attempt = attempt,
        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      )
    })
    # If last attempt succeeded, function already returned.
    # If error was stored, check if retryable (empty reasoning = stochastic).
    if (!is.null(errors[[model]]) && attempt < max_retries) {
      is_retryable <- grepl("empty/missing reasoning", errors[[model]]$error)
      if (is_retryable) next
    }
    break  # Hard failure or max retries reached — move to next model
    }  # end retry loop
  }

  # All models failed - construct informative error message
  error_messages <- sapply(names(errors), function(model) {
    err <- errors[[model]]
    paste(model, "-", err$error)
  })

  error_summary <- paste(
    sprintf("All models failed for %s:", step_name),
    paste(error_messages, collapse = "\n"),
    sep = "\n"
  )

  error_log_json <- jsonlite::toJSON(errors, auto_unbox = TRUE, pretty = TRUE)

  cnd <- simpleError(error_summary)
  cnd$error_log <- error_log_json
  stop(cnd)
}
