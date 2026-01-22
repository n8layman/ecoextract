# LLM Deduplication Method

## Goal

Add a standalone LLM-based deduplication function. Integrate as third method alongside existing jaccard and embedding methods.

## Current Methods

1. **jaccard** (default): Character trigram similarity, O(n*m) comparisons, free
2. **embedding**: Cosine similarity of embeddings, O(n*m) API calls
3. **llm** (new): Single LLM call, semantic matching

## Design

`llm_deduplicate()` is standalone - takes two dataframes and key fields, returns indices. No dependencies on other ecoextract code. Can be used independently or via `deduplicate_records(similarity_method = "llm")`.

## Files to Create

### 1. `inst/prompts/deduplication_prompt.md`

```markdown
Compare new records against existing records. Return the indices (1-based) of new records that are NOT duplicates.

Two records are duplicates if they represent the same entity, even with different spelling, abbreviations, or synonyms.
```

## Files to Modify

### 2. `R/deduplication.R`

Add standalone helper:

```r
#' LLM-based deduplication
#'
#' Compare new records against existing records using an LLM.
#' Returns indices of new records that are NOT duplicates.
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
```

Modify `deduplicate_records()`:
- Add `model` parameter
- Add `"llm"` case before the loop:

```r
if (similarity_method == "llm") {
  unique_indices <- llm_deduplicate(new_records, existing_records, key_fields, model)
  duplicates_found <- nrow(new_records) - length(unique_indices)
} else {
  # existing jaccard/embedding loop
}
```

### 3. `R/extraction.R`

Pass `model` to `deduplicate_records()`:

```r
dedup_result <- deduplicate_records(
  ...,
  model = model
)
```

### 4. Docs

Update roxygen in workflow.R and extraction.R to mention "llm" as third option.

## Implementation Order

1. Create `inst/prompts/deduplication_prompt.md`
2. Add `llm_deduplicate()` helper to deduplication.R
3. Modify `deduplicate_records()` to add llm case
4. Pass `model` param in extraction.R
5. Update docs
6. Add test
