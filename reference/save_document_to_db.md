# Save or reprocess a document in the EcoExtract database

Inserts a new document row into the \`documents\` table, automatically
computing file hash if not provided. Optionally, if \`overwrite =
TRUE\`, any existing document with the same file hash is deleted
(including associated records), and the new row preserves the old
\`document_id\`.

## Usage

``` r
save_document_to_db(
  db_conn,
  file_path,
  file_hash = NULL,
  metadata = list(),
  overwrite = FALSE,
  document_id = NULL
)
```

## Arguments

- db_conn:

  A DBI connection object or a path to an SQLite database file.

- file_path:

  Path to the PDF or document file to store.

- file_hash:

  Optional precomputed file hash (MD5). If \`NULL\`, it is computed
  automatically from the file.

- metadata:

  A named list of OCR results. Recognized keys:

  document_content

  :   OCR or processed content.

  ocr_images

  :   OCR images (as JSON array or similar).

  ocr_provider

  :   OCR provider that succeeded.

  ocr_log

  :   JSON audit trail of failed OCR attempts.

  Metadata schema fields are saved separately by
  [`save_metadata_to_db()`](https://n8layman.github.io/ecoextract/reference/save_metadata_to_db.md).

- overwrite:

  Logical; if \`TRUE\`, any existing row with the same file hash is
  deleted and the new row preserves the old \`document_id\`.

## Value

The \`document_id\` of the inserted or replaced row, or \`NULL\` if
insertion fails.

## Examples

``` r
if (FALSE) { # \dontrun{
db <- "ecoextract_results.sqlite"
save_document_to_db(db, "example.pdf",
                    metadata = list(document_content = "OCR text"), overwrite = TRUE)
} # }
```
