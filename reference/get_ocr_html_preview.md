# Get OCR HTML Preview

Render OCR results as HTML with embedded images

## Usage

``` r
get_ocr_html_preview(
  document_id,
  db_conn = "ecoextract_records.db",
  page_num = 1
)
```

## Arguments

- document_id:

  Document ID

- db_conn:

  Database connection (any DBI backend) or path to SQLite database file.
  Defaults to "ecoextract_records.db"

- page_num:

  Page number to render (default: 1, use "all" for all pages)

## Value

Browsable HTML object for display in RStudio viewer

## Examples

``` r
if (FALSE) { # \dontrun{
# Using default SQLite database
html <- get_ocr_html_preview(1)
print(html)  # Opens in RStudio viewer

# Using explicit connection
db <- DBI::dbConnect(RSQLite::SQLite(), "ecoextract.sqlite")
html <- get_ocr_html_preview(1, db)
print(html)  # Opens in RStudio viewer
DBI::dbDisconnect(db)
} # }
```
