# Get array field names from schema definition

Identifies fields defined as arrays in the JSON schema.

## Usage

``` r
get_schema_array_fields(schema_list)
```

## Arguments

- schema_list:

  Parsed JSON schema (from jsonlite::fromJSON)

## Value

Character vector of array field names
