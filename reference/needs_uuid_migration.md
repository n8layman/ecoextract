# Check whether the records table uses the old integer-id schema

Returns TRUE if \`records.id\` is INTEGER (pre-0.1.13 schema), FALSE
otherwise. Used by
[`get_records()`](https://n8layman.github.io/ecoextract/reference/get_records.md)
(warn) and
[`save_document()`](https://n8layman.github.io/ecoextract/reference/save_document.md)
(error) to surface migration need at actual database-use time rather
than at init time.

## Usage

``` r
needs_uuid_migration(con)
```

## Arguments

- con:

  An open DBI connection.
