# OCR Functions

Functions for performing OCR on PDF documents Perform OCR on PDF

## Usage

``` r
perform_ocr(pdf_file, provider = "tensorlake", timeout = 60)
```

## Arguments

- pdf_file:

  Path to PDF

- provider:

  OCR provider to use (default: "tensorlake")

- timeout:

  Maximum seconds to wait for OCR completion (default: 60)

## Value

List with markdown content, images, and raw result
