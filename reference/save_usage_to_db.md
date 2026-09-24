# Save a step's token usage to the documents table (internal)

Save a step's token usage to the documents table (internal)

## Usage

``` r
save_usage_to_db(con, document_id, step, usage)
```

## Arguments

- con:

  Database connection

- document_id:

  Document ID

- step:

  LLM step name ("metadata", "extraction", or "refinement")

- usage:

  Usage list from
  [`chat_usage()`](https://n8layman.github.io/ecoextract/reference/chat_usage.md),
  or NULL when no LLM call was made (stored as NULL)

## Value

NULL (invisibly)
