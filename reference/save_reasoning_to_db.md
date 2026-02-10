# Save reasoning to database (internal)

Save reasoning to database (internal)

## Usage

``` r
save_reasoning_to_db(
  document_id,
  db_conn,
  reasoning_text,
  step = c("extraction", "refinement")
)
```

## Arguments

- document_id:

  Document ID

- db_conn:

  Database connection

- reasoning_text:

  Reasoning text to save

- step:

  Either "extraction" or "refinement"
