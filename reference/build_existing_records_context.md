# Build existing records context for LLM prompts

Build existing records context for LLM prompts

## Usage

``` r
build_existing_records_context(
  existing_records,
  document_id = NULL,
  include_record_id = FALSE
)
```

## Arguments

- existing_records:

  Dataframe of existing records

- document_id:

  Optional document ID for context

- include_record_id:

  Whether to include record_id (TRUE for refinement, FALSE for
  extraction)

## Value

Character string with existing records formatted for LLM context
