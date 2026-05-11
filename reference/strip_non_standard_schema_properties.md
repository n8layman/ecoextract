# Strip non-standard JSON Schema properties recursively

Removes properties that waste tokens and some providers reject:
additionalProperties, \$schema, \_comment, and x-\* extensions.

## Usage

``` r
strip_non_standard_schema_properties(x)
```

## Arguments

- x:

  List representing a JSON schema

## Value

List with non-standard properties removed
