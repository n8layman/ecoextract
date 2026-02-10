# Get document content (OCR results) from database (internal)

Get document content (OCR results) from database (internal)

## Usage

``` r
get_document_content(document_id, db_conn)
```

## Arguments

- document_id:

  Document ID to retrieve

- db_conn:

  Database connection

## Value

Character string with OCR markdown content, or NA if not found
