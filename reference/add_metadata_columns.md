# Add documents table columns for metadata schema fields (internal)

Adds a column for each metadata field not already in the documents
table. Metadata columns come only from the metadata schema in use; the
package default schema gives the bibliographic fields for journal
articles.

## Usage

``` r
add_metadata_columns(con, schema_list)
```

## Arguments

- con:

  Database connection

- schema_list:

  Parsed metadata JSON schema

## Value

NULL (invisibly)
