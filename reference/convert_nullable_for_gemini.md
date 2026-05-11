# Convert nullable type arrays to Gemini's nullable format

JSON Schema uses `"type": ["string", "null"]` for nullable fields.
Gemini requires `"type": "string", "nullable": true` instead.

## Usage

``` r
convert_nullable_for_gemini(x)
```

## Arguments

- x:

  List representing a JSON schema

## Value

List with nullable types converted
