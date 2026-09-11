# Load the metadata JSON schema (internal)

Uses the config priority order: an explicit file, then
`ecoextract/metadata_schema.json` in the project directory, then the
package default.

## Usage

``` r
load_metadata_schema(schema_file = NULL)
```

## Arguments

- schema_file:

  Path to custom metadata schema JSON file (optional)

## Value

Parsed metadata JSON schema as a list
