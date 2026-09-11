# Add documents table columns for metadata schema fields (internal)

Adds a column for each metadata field not already in the documents
table. The default bibliographic fields already exist, so this only
changes the table when a custom metadata schema is in use.

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
