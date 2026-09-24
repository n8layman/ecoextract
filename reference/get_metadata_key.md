# Get the name of a metadata schema's metadata object (internal)

The metadata schema wraps its fields in a single object under
`properties`. The package default calls it `publication_metadata`;
custom schemas can use any name.

## Usage

``` r
get_metadata_key(schema_list)
```

## Arguments

- schema_list:

  Parsed metadata JSON schema

## Value

Character name of the metadata object
