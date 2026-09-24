# Get the metadata fields that form record IDs (internal)

Reads `x-record-id-fields` from the metadata schema's metadata object
(see
[`get_metadata_key()`](https://n8layman.github.io/ecoextract/reference/get_metadata_key.md)).
Each entry must be a metadata field, `document_id`, or `file_name`.

## Usage

``` r
get_record_id_fields(schema_list)
```

## Arguments

- schema_list:

  Parsed metadata JSON schema

## Value

Character vector of field names
