# Export Database

Export records joined with document metadata. Every document is
included: a document with no records appears as one row with empty
record columns, and its `extraction_status` and `records_extracted` show
whether it was processed.

## Usage

``` r
export_db(
  document_id = NULL,
  db_conn = "ecoextract_records.db",
  include_ocr = FALSE,
  simple = FALSE,
  filename = NULL,
  metadata_schema_file = NULL
)
```

## Arguments

- document_id:

  Optional document ID to filter by (NULL for all documents)

- db_conn:

  Database connection (any DBI backend) or path to SQLite database file.
  Defaults to "ecoextract_records.db"

- include_ocr:

  If TRUE, include OCR content in export (default: FALSE)

- simple:

  If TRUE, return only minimal document columns (document_id, file_name,
  and the metadata schema's `x-record-id-fields`) plus schema-defined
  record fields, excluding record metadata like id,
  extraction_timestamp, and prompt_hash (default: FALSE)

- filename:

  Optional path to save as CSV file (if NULL, returns tibble only)

- metadata_schema_file:

  Path to custom metadata schema JSON file (optional). Its fields are
  the document metadata columns in the export.

## Value

Tibble with records joined to document metadata, or invisibly if saved
to file

## Examples

``` r
if (FALSE) { # \dontrun{
# Get all records with metadata as tibble
data <- export_db()

# Get records for specific document
data <- export_db(document_id = 1)

# Export to CSV
export_db(filename = "extracted_data.csv")

# Include OCR content
data <- export_db(include_ocr = TRUE)

# Simplified output (no processing metadata)
data <- export_db(simple = TRUE)
} # }
```
