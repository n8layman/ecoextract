# Add the document_edits audit table (internal)

Records each document field a reviewer changes in
[`save_document()`](https://n8layman.github.io/ecoextract/reference/save_document.md),
the way `record_edits` does for records. Model runs never overwrite a
field listed here (see
[`save_metadata_to_db()`](https://n8layman.github.io/ecoextract/reference/save_metadata_to_db.md)).
Safe to run on any database; creates the table only if it is missing.

## Usage

``` r
add_document_edits_table(con)
```

## Arguments

- con:

  Database connection

## Value

NULL (invisibly)
