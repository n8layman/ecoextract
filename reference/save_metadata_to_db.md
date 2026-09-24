# Save document metadata to EcoExtract database (internal)

Writes a metadata extraction result to the document's row. With
`coalesce = TRUE`, only fields that are currently empty are filled and
existing values are kept. With `coalesce = FALSE`, every field is
written exactly as given, NULLs included, so an empty result clears the
field. Fields a reviewer edited (listed in `document_edits`) are never
written, whichever mode is used.

## Usage

``` r
save_metadata_to_db(
  document_id,
  db_conn,
  metadata = list(),
  metadata_llm_model = NULL,
  metadata_log = NULL,
  coalesce = TRUE
)
```

## Arguments

- document_id:

  Document ID to update

- db_conn:

  Database connection or path to SQLite database

- metadata:

  Named list with metadata fields

- metadata_llm_model:

  Model that produced the metadata

- metadata_log:

  JSON audit log of failed attempts

- coalesce:

  Logical. TRUE (default) fills empty fields and keeps existing values;
  FALSE replaces every field, including with NULL.

## Value

Document ID
