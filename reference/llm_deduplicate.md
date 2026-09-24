# LLM-based deduplication

Compare new records against existing records using an LLM. Returns
indices of new records that are NOT duplicates. This is a standalone
function with no dependencies on other ecoextract code.

## Usage

``` r
llm_deduplicate(
  new_records,
  existing_records,
  key_fields,
  model = "anthropic/claude-sonnet-5",
  reasoning_effort = NULL
)
```

## Arguments

- new_records:

  Dataframe of new records

- existing_records:

  Dataframe of existing records

- key_fields:

  Character vector of column names to compare

- model:

  LLM model (default: "anthropic/claude-sonnet-5")

- reasoning_effort:

  Thinking effort (e.g. "low", "high"), or NULL (default) for thinking
  off

## Value

List with unique_indices (integer vector of 1-based indices of unique
new records) and usage (token usage of the LLM call)
