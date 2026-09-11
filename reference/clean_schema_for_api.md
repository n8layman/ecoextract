# Clean a TypeJsonSchema for API use

Strips non-standard properties. For Gemini, also converts nullable
types; for all other providers, sets `additionalProperties: false` on
every object.

## Usage

``` r
clean_schema_for_api(schema, gemini = FALSE)
```

## Arguments

- schema:

  An ellmer TypeJsonSchema object

- gemini:

  Logical. If TRUE, apply Gemini's schema format.

## Value

A new TypeJsonSchema with properties cleaned
