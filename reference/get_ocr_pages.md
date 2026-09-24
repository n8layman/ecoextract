# Get OCR Pages

Retrieve a document's OCR text as markdown, one element per page. With
`embed_images = TRUE`, each image placeholder in a page (for example
`![img-0.jpeg](img-0.jpeg)`) is replaced by an `<img>` tag carrying the
image stored in `ocr_images` for that page, matched by the image's
stored `id`. Placeholders with no stored image become their alt text.

## Usage

``` r
get_ocr_pages(
  document_id,
  db_conn = "ecoextract_records.db",
  embed_images = TRUE
)
```

## Arguments

- document_id:

  Document ID

- db_conn:

  Database connection (any DBI backend) or path to SQLite database file.
  Defaults to "ecoextract_records.db"

- embed_images:

  If TRUE (default), embed stored images in place of their placeholders

## Value

Character vector of page markdown, one element per page

## Details

Requires OCR output with page markdown (Mistral). Providers that store
structured page fields instead, such as Tensorlake, have no page
markdown.

## Examples

``` r
if (FALSE) { # \dontrun{
pages <- get_ocr_pages(1)
cat(pages[1])
} # }
```
