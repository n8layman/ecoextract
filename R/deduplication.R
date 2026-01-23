#' Deduplication Functions
#'
#' Functions for semantic deduplication of extracted records using embeddings

#' Canonicalize text field for embedding
#'
#' Normalizes text fields to improve embedding consistency:
#' - Unicode normalization (NFC)
#' - Lowercase
#' - Trim whitespace
#'
#' @param text Character vector to normalize
#' @return Normalized character vector
#' @keywords internal
canonicalize <- function(text) {
  if (is.null(text) || all(is.na(text))) {
    return(text)
  }

  text |>
    stringi::stri_trans_nfc() |>
    tolower() |>
    stringr::str_trim()
}

#' Calculate cosine similarity between two vectors
#'
#' @param vec1 Numeric vector (embedding)
#' @param vec2 Numeric vector (embedding)
#' @return Numeric similarity score (0-1)
#' @keywords internal
cosine_similarity <- function(vec1, vec2) {
  if (length(vec1) != length(vec2)) {
    stop("Vectors must have same length")
  }

  dot_product <- sum(vec1 * vec2)
  norm1 <- sqrt(sum(vec1^2))
  norm2 <- sqrt(sum(vec2^2))

  if (norm1 == 0 || norm2 == 0) {
    return(0)
  }

  dot_product / (norm1 * norm2)
}

#' Calculate Jaccard similarity between two strings
#'
#' Tokenizes strings into character n-grams and calculates Jaccard similarity.
#' This is a fast, non-API-dependent method for string comparison.
#'
#' @param str1 First string
#' @param str2 Second string
#' @param n N-gram size (default: 3 for trigrams)
#' @return Numeric similarity score (0-1)
#' @keywords internal
jaccard_similarity <- function(str1, str2, n = 3) {
  if (is.null(str1) || is.null(str2) || is.na(str1) || is.na(str2)) {
    return(0)
  }

  # Convert to character
  str1 <- as.character(str1)
  str2 <- as.character(str2)

  # Handle empty strings before canonicalization
  if (nchar(str1) == 0 && nchar(str2) == 0) {
    return(1)
  }
  if (nchar(str1) == 0 || nchar(str2) == 0) {
    return(0)
  }

  # Canonicalize (lowercase, trim, unicode normalize)
  str1 <- canonicalize(str1)
  str2 <- canonicalize(str2)

  # Check for exact match after canonicalization
  if (str1 == str2) {
    return(1)
  }

  # Generate n-grams
  ngrams1 <- character(0)
  if (nchar(str1) >= n) {
    ngrams1 <- sapply(1:(nchar(str1) - n + 1), function(i) substr(str1, i, i + n - 1))
  }

  ngrams2 <- character(0)
  if (nchar(str2) >= n) {
    ngrams2 <- sapply(1:(nchar(str2) - n + 1), function(i) substr(str2, i, i + n - 1))
  }

  # Handle cases where strings are shorter than n
  if (length(ngrams1) == 0 || length(ngrams2) == 0) {
    # Fall back to exact match (already checked above)
    return(0)
  }

  # Calculate Jaccard similarity
  intersection <- length(intersect(ngrams1, ngrams2))
  union <- length(unique(c(ngrams1, ngrams2)))

  if (union == 0) return(0)

  intersection / union
}

#' LLM-based deduplication
#'
#' Compare new records against existing records using an LLM.
#' Returns indices of new records that are NOT duplicates.
#' This is a standalone function with no dependencies on other ecoextract code.
#'
#' @param new_records Dataframe of new records
#' @param existing_records Dataframe of existing records
#' @param key_fields Character vector of column names to compare
#' @param model LLM model (default: "anthropic/claude-sonnet-4-5")
#' @return Integer vector of 1-based indices of unique new records
#' @keywords internal
llm_deduplicate <- function(new_records, existing_records, key_fields,
                            model = "anthropic/claude-sonnet-4-5") {
  # Format as JSON (only key fields)
  new_json <- jsonlite::toJSON(new_records[, key_fields, drop = FALSE], auto_unbox = TRUE)
  existing_json <- jsonlite::toJSON(existing_records[, key_fields, drop = FALSE], auto_unbox = TRUE)

  # Load prompt
  prompt_path <- system.file("prompts", "deduplication_prompt.md", package = "ecoextract")
  prompt <- paste(readLines(prompt_path, warn = FALSE), collapse = "\n")

  # Build context
  context <- glue::glue("
Key fields: {paste(key_fields, collapse = ', ')}

Existing records:
{existing_json}

New records:
{new_json}
")

  # Schema using ellmer native types
  schema <- ellmer::type_object(
    unique_indices = ellmer::type_array(items = ellmer::type_integer())
  )

  # Call LLM
  chat <- ellmer::chat(name = model, system_prompt = prompt, echo = "none")
  result <- chat$chat_structured(context, type = schema)

  # Return indices (default to all if empty)
  indices <- result$unique_indices
  if (is.null(indices) || length(indices) == 0) {
    return(seq_len(nrow(new_records)))
  }
  as.integer(indices)
}

#' Deduplicate records using semantic similarity
#'
#' Compares new records against existing records using embeddings
#' of composite keys. Only inserts records that don't match existing
#' records above the similarity threshold.
#'
#' @param new_records Dataframe of newly extracted records
#' @param existing_records Dataframe of existing records from database
#' @param schema_list Parsed JSON schema (list) containing required fields
#' @param min_similarity Minimum cosine similarity to consider a duplicate (default: 0.9)
#' @param embedding_provider Provider for embeddings (default: "mistral")
#' @param similarity_method Method for similarity calculation: "embedding", "jaccard", or "llm" (default: "llm")
#' @param model LLM model for llm method (default: "anthropic/claude-sonnet-4-5")
#' @return List with deduplicated records and metadata
#' @keywords internal
deduplicate_records <- function(new_records,
                                existing_records,
                                schema_list,
                                min_similarity = 0.9,
                                embedding_provider = "mistral",
                                similarity_method = "llm",
                                model = "anthropic/claude-sonnet-4-5") {

  # Extract unique fields from schema for deduplication
  # Navigate to the record items schema (schema_list is the full schema)
  record_schema <- schema_list$properties$records$items

  if (is.null(record_schema)) {
    stop("Invalid schema structure: could not find properties > records > items")
  }

  # Get x-unique-fields from the record schema (should be an array like 'required')
  key_fields <- record_schema[["x-unique-fields"]]

  if (is.null(key_fields) || length(key_fields) == 0) {
    stop(
      "Schema must define 'x-unique-fields' at properties > records > items level to specify which fields define record uniqueness. ",
      "Add 'x-unique-fields': [\"field1\", \"field2\", ...] to the record schema items, as a sibling to 'required'."
    )
  }

  # Validate that all key fields exist in record schema properties
  if (!is.null(record_schema$properties)) {
    schema_field_names <- names(record_schema$properties)
    invalid_fields <- setdiff(key_fields, schema_field_names)
    if (length(invalid_fields) > 0) {
      stop(glue::glue(
        "Invalid x-unique-fields in schema: {paste(invalid_fields, collapse = ', ')}. ",
        "These fields are not defined in record schema properties. ",
        "Available fields: {paste(schema_field_names, collapse = ', ')}"
      ))
    }
  }

  # If no existing records, all new records are unique
  if (is.null(existing_records) || nrow(existing_records) == 0) {
    return(list(
      unique_records = new_records,
      duplicates_found = 0,
      new_records_count = nrow(new_records)
    ))
  }

  # If no new records, nothing to do
  if (nrow(new_records) == 0) {
    return(list(
      unique_records = tibble::tibble(),
      duplicates_found = 0,
      new_records_count = 0
    ))
  }

  message(glue::glue("Deduplicating {nrow(new_records)} new records against {nrow(existing_records)} existing records"))
  message(glue::glue("Using field-by-field comparison with key fields: {paste(key_fields, collapse = ', ')}"))
  message(glue::glue("Similarity method: {similarity_method}"))

  # LLM method: single API call for all comparisons

  if (similarity_method == "llm") {
    unique_indices <- llm_deduplicate(new_records, existing_records, key_fields, model)
    duplicates_found <- nrow(new_records) - length(unique_indices)

    # Log results
    for (i in seq_len(nrow(new_records))) {
      if (i %in% unique_indices) {
        message(glue::glue("  Record {i}: Unique (no matching existing record)"))
      } else {
        message(glue::glue("  Record {i}: Duplicate (identified by LLM)"))
      }
    }
  } else {
    # Jaccard/embedding methods: field-by-field comparison

    # Convert provider string to function call (only needed for embedding method)
    provider_fn <- NULL
    if (similarity_method == "embedding") {
      provider_fn <- switch(embedding_provider,
        "mistral" = tidyllm::mistral,
        "openai" = tidyllm::openai,
        "voyage" = tidyllm::voyage,
        stop("Unsupported embedding provider: ", embedding_provider)
      )
    }

    # Process each new record
    unique_indices <- c()
    duplicates_found <- 0

    for (i in seq_len(nrow(new_records))) {
    new_record <- new_records[i, ]
    is_duplicate <- FALSE

    # Compare this new record against each existing record
    for (j in seq_len(nrow(existing_records))) {
      existing_record <- existing_records[j, ]

      # Field-by-field comparison
      fields_compared <- c()
      field_similarities <- c()
      all_fields_match <- TRUE

      for (field in key_fields) {
        new_val <- new_record[[field]]
        existing_val <- existing_record[[field]]

        # Only compare if BOTH records have this field populated
        new_populated <- !is.null(new_val) && !is.na(new_val) && nchar(as.character(new_val)) > 0
        existing_populated <- !is.null(existing_val) && !is.na(existing_val) && nchar(as.character(existing_val)) > 0

        if (new_populated && existing_populated) {
          # Canonicalize both values
          new_canonical <- canonicalize(as.character(new_val))
          existing_canonical <- canonicalize(as.character(existing_val))

          # Calculate similarity based on method
          if (similarity_method == "jaccard") {
            similarity <- jaccard_similarity(new_canonical, existing_canonical)
          } else {
            # Generate embeddings for this field
            embeddings_result <- tidyllm::embed(c(new_canonical, existing_canonical), .provider = provider_fn())
            new_emb <- embeddings_result$embeddings[[1]]
            existing_emb <- embeddings_result$embeddings[[2]]

            # Calculate similarity
            similarity <- cosine_similarity(new_emb, existing_emb)
          }

          fields_compared <- c(fields_compared, field)
          field_similarities <- c(field_similarities, similarity)

          # If ANY field fails threshold, this existing record is not a match
          if (similarity < min_similarity) {
            all_fields_match <- FALSE
            break  # Stop comparing fields, move to next existing record
          }
        }
      }

      # If we compared at least one field AND all passed threshold → duplicate
      if (length(fields_compared) > 0 && all_fields_match) {
        is_duplicate <- TRUE
        duplicates_found <- duplicates_found + 1
        message(glue::glue("  Record {i}: Duplicate of existing record {j} (fields: {paste(fields_compared, collapse = ', ')}, similarities: {paste(round(field_similarities, 3), collapse = ', ')})"))
        break  # Found a match, no need to check other existing records
      }
    }

    # If not a duplicate of any existing record, it's unique
    if (!is_duplicate) {
      unique_indices <- c(unique_indices, i)
      message(glue::glue("  Record {i}: Unique (no matching existing record)"))
    }
  }
  }  # End else (jaccard/embedding methods)

  # Return unique records
  unique_records <- if (length(unique_indices) > 0) {
    new_records[unique_indices, ]
  } else {
    tibble::tibble()
  }

  message(glue::glue("Deduplication complete: {nrow(unique_records)} unique, {duplicates_found} duplicates"))

  list(
    unique_records = unique_records,
    duplicates_found = duplicates_found,
    new_records_count = nrow(unique_records)
  )
}
