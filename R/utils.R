#' Internal utility functions

#' Create record IDs for a batch of records (internal)
#' @param interactions Dataframe of records
#' @param author_lastname Author lastname for ID generation
#' @param publication_year Publication year for ID generation
#' @return Dataframe with record_id column added
#' @keywords internal
add_record_ids <- function(interactions, author_lastname, publication_year) {
  if (nrow(interactions) == 0) {
    return(interactions)
  }

  # Generate sequential record IDs
  interactions$record_id <- sapply(1:nrow(interactions), function(i) {
    generate_record_id(author_lastname, publication_year, i)
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
                     "llm_model_version", "prompt_hash",
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
    "google" = "GOOGLE_API_KEY"
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
#' @param models Character vector of model names (e.g., c("anthropic/claude-sonnet-4-5", "mistral/mistral-large-latest"))
#' @param system_prompt System prompt for the LLM
#' @param context User context/input for the LLM
#' @param schema ellmer type schema for structured output
#' @param max_tokens Maximum tokens for response (default 16384)
#' @param step_name Name of the step for logging (default "LLM call")
#' @return List with result (structured output), model_used (which model succeeded), and error_log (JSON string of failed attempts)
#' @keywords internal
try_models_with_fallback <- function(
  models,
  system_prompt,
  context,
  schema,
  max_tokens = 16384,
  step_name = "LLM call"
) {
  # Ensure models is a character vector
  if (!is.character(models) || length(models) == 0) {
    stop("models must be a non-empty character vector")
  }

  # Check that API keys exist for all models in the list
  check_api_keys_for_models(models)

  errors <- list()

  for (model in models) {
    tryCatch({
      # Create chat instance
      chat <- ellmer::chat(
        name = model,
        system_prompt = system_prompt,
        echo = "none",
        params = list(max_tokens = max_tokens)
      )

      # Attempt structured chat
      result <- chat$chat_structured(context, type = schema)

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
      # Check if this was a refusal
      is_refusal <- FALSE
      tryCatch({
        turns <- chat$get_turns()
        if (length(turns) > 0) {
          last_turn <- turns[[length(turns)]]
          if (!is.null(last_turn@json$stop_reason) &&
              last_turn@json$stop_reason == "refusal") {
            is_refusal <- TRUE
          }
        }
      }, error = function(e2) {
        # If we can't check turns, treat as regular error
      })

      error_type <- if (is_refusal) "refusal" else "error"
      message(sprintf("%s %s with %s: %s", step_name, error_type, model, conditionMessage(e)))

      # Store error for audit log (use <<- to modify parent scope)
      errors[[model]] <<- list(
        type = error_type,
        message = conditionMessage(e),
        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      )
    })
  }

  # All models failed - construct informative error message
  error_summary <- paste(
    sprintf("All models failed for %s:", step_name),
    paste(names(errors), purrr::map_chr(errors, ~paste(.x$type, ":", .x$message)), sep = " - ", collapse = "\n"),
    sep = "\n"
  )

  stop(error_summary)
}
