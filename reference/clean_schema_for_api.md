# Clean a TypeJsonSchema for API use

Strips non-standard properties. For Gemini, also converts nullable
types.

## Usage

``` r
clean_schema_for_api(schema, gemini = FALSE)
```

## Arguments

- schema:

  An ellmer TypeJsonSchema object

- gemini:

  Logical. If TRUE, also convert nullable type arrays.

## Value

A new TypeJsonSchema with properties cleaned
