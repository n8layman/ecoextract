# Extract Publication Metadata

Extracts publication metadata from OCR-processed scientific documents: -
Title, authors, publication year, DOI, journal - Saves results to
documents table

## Usage

``` r
extract_metadata(
  document_id,
  db_conn,
  force_reprocess = TRUE,
  model = "anthropic/claude-sonnet-4-5"
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
  "anthropic/claude-sonnet-4-5")

## Value

List with status ("completed"/\<error message\>) and document_id

## Details

This is a schema-agnostic step that extracts universal publication
metadata regardless of the domain-specific extraction schema used in
later steps. Skip logic is handled by the workflow - this function
always runs when called.
