# Save publication metadata to EcoExtract database (internal)

Updates existing document metadata fields that are currently
NULL/NA/empty. Optionally overwrites all metadata if \`overwrite =
TRUE\`.

## Usage

``` r
save_metadata_to_db(
  document_id,
  db_conn,
  metadata = list(),
  metadata_llm_model = NULL,
  metadata_log = NULL,
  overwrite = FALSE
)
```

## Arguments

- document_id:

  Document ID to update

- db_conn:

  Database connection or path to SQLite database

- metadata:

  Named list with metadata fields

- overwrite:

  Logical, if TRUE will overwrite all existing fields

## Value

Document ID
