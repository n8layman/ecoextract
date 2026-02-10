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

- ...:

  Additional metadata fields to update on the document

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
