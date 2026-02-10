# Data Access Functions

Functions for retrieving OCR results, audit data, and extracted records
from the database Get OCR Markdown

## Usage

``` r
get_ocr_markdown(document_id, db_conn = "ecoextract_records.db")
```

## Arguments

- document_id:

  Document ID

- db_conn:

  Database connection (any DBI backend) or path to SQLite database file.
  Defaults to "ecoextract_records.db"

## Value

Character string with markdown content, or NA if not found

## Details

Retrieve OCR markdown text for a document

## Examples

``` r
if (FALSE) { # \dontrun{
# Using default SQLite database
markdown <- get_ocr_markdown(1)

# Using explicit connection
db <- DBI::dbConnect(RSQLite::SQLite(), "ecoextract.sqlite")
markdown <- get_ocr_markdown(1, db)
DBI::dbDisconnect(db)
} # }
```
