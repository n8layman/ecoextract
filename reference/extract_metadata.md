# Extract Document Metadata

Extracts document-level metadata from OCR-processed documents and saves
it to the documents table. The fields come from the metadata schema,
loaded with the usual config priority (explicit file, then
`ecoextract/metadata_schema.json`, then the package default of
bibliographic fields for journal articles). Skip logic is handled by the
workflow - this function always runs when called.

## Usage

``` r
extract_metadata(
  document_id,
  db_conn,
  force_reprocess = TRUE,
  model = "anthropic/claude-sonnet-5",
  metadata_schema_file = NULL,
  metadata_prompt_file = NULL
)
```

## Arguments

- document_id:

  Document ID in database

- db_conn:

  Database connection

- force_reprocess:

  Ignored (kept for backward compatibility). Skip logic handled by
  workflow.

- model:

  LLM model for metadata extraction (default:
  "anthropic/claude-sonnet-5")

- metadata_schema_file:

  Path to custom metadata schema JSON file (optional)

- metadata_prompt_file:

  Path to custom metadata prompt file (optional)

## Value

List with status ("completed"/\<error message\>), document_id, and usage
(token usage across all attempts, NULL if no LLM call was made)
