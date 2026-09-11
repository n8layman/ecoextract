# Get the JSON type of a schema property (internal)

For nullable types like `["string", "null"]`, returns the first non-null
type. Properties without a type are treated as strings.

## Usage

``` r
json_property_type(field_spec)
```

## Arguments

- field_spec:

  Property definition from a parsed JSON schema

## Value

JSON type name
