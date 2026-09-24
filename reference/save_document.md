# Save Document After Human Review

Updates document metadata with review timestamp and saves modified
records, tracking edits in the record_edits audit table. Designed for
Shiny app review workflows.

## Usage

``` r
save_document(
  document_id,
  records_df,
  original_df = NULL,
  db_conn = "ecoextract_records.db",
  metadata_schema_file = NULL,
  ...
)
```

## Arguments

- document_id:

  Document ID to update

- records_df:

  Updated records dataframe (from Shiny editor)

- original_df:

  Original records dataframe (before edits, for diff). If NULL, only
  updates reviewed_at timestamp without modifying records.

- db_conn:

  Database connection or path to SQLite database file

- metadata_schema_file:

  Optional path to a metadata JSON schema file. Its `x-record-id-fields`
  determine IDs for records added during review. Defaults to
  `ecoextract/metadata_schema.json` or the package default.

- ...:

  Additional metadata fields to update on the document. Fields whose
  value changes are logged in the `document_edits` table, and later
  metadata runs leave them unchanged.

## Value

Invisibly returns the document_id

## Examples

``` r
if (FALSE) { # \dontrun{
# In Shiny app "Accept" button handler
save_document(
  document_id = input$document_select,
  records_df = edited_records(),
  original_df = original_records(),
  db_conn = db_path
)
} # }
```
