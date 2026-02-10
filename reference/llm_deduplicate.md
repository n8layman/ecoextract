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
  model = "anthropic/claude-sonnet-4-5"
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

  LLM model (default: "anthropic/claude-sonnet-4-5")

## Value

Integer vector of 1-based indices of unique new records
