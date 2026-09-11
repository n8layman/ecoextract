# Get the record ID prefix for a document in the database (internal)

Looks up the document's values for the fields named in the metadata
schema's `x-record-id-fields`. `file_name` is used without its
extension.

## Usage

``` r
get_record_id_prefix(con, document_id, metadata_schema_file = NULL)
```

## Arguments

- con:

  Database connection

- document_id:

  Document ID

- metadata_schema_file:

  Path to custom metadata schema JSON file (optional)

## Value

Character record ID prefix
