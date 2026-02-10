# OCR Document and Save to Database

Performs OCR on PDF and saves document to database. Skip logic is
handled by the workflow - this function always runs OCR when called.

## Usage

``` r
ocr_document(pdf_file, db_conn, force_reprocess = TRUE, max_wait_seconds = 60)
```

## Arguments

- pdf_file:

  Path to PDF file

- db_conn:

  Database connection

- force_reprocess:

  Ignored (kept for backward compatibility). Skip logic handled by
  workflow.

- max_wait_seconds:

  Maximum seconds to wait for OCR completion (default: 60)

## Value

List with status ("completed"/\<error message\>) and document_id
