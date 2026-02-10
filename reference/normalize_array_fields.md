# Validate required array fields based on schema definition (schema-agnostic)

Validates that required array fields have values. Array normalization
(flattening nested lists) is handled during serialization in
save_records_to_db to avoid vctrs type-checking issues with tibble
column assignment.

## Usage

``` r
normalize_array_fields(df, schema_list)
```

## Arguments

- df:

  Dataframe with extracted records

- schema_list:

  Parsed JSON schema (from jsonlite::fromJSON)

## Value

Validated dataframe (unmodified)
