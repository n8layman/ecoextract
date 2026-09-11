# Strip non-standard JSON Schema properties recursively

Removes properties that waste tokens and some providers reject:
additionalProperties, \$schema, \_comment, and x-\* extensions.
[`clean_schema_for_api()`](https://n8layman.github.io/ecoextract/reference/clean_schema_for_api.md)
sets additionalProperties back to false for providers that require it.

## Usage

``` r
strip_non_standard_schema_properties(x)
```

## Arguments

- x:

  List representing a JSON schema

## Value

List with non-standard properties removed
