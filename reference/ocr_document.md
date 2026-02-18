# OCR Document and Save to Database

Performs OCR on PDF and saves document to database. Skip logic is
handled by the workflow - this function always runs OCR when called.

## Usage

``` r
ocr_document(
  pdf_file,
  db_conn,
  force_reprocess = TRUE,
  provider = "tensorlake",
  timeout = 60,
  max_wait_seconds = NULL
)
```

## Arguments

- pdf_file:

  Path to PDF file

- db_conn:

  Database connection

- force_reprocess:

  Ignored (kept for backward compatibility). Skip logic handled by
  workflow.

- provider:

  OCR provider to use (default: "tensorlake")

- timeout:

  Maximum seconds to wait for OCR completion (default: 60)

- max_wait_seconds:

  Deprecated. Use timeout instead.

## Value

List with status ("completed"/\<error message\>) and document_id
