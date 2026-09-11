# Set additionalProperties to false on every object in a JSON schema

Anthropic and OpenAI structured outputs expect
`"additionalProperties": false` on every object, and some models (e.g.
Claude Sonnet 4.6) reject schemas without it. Gemini rejects the
keyword, so this is not applied there.

## Usage

``` r
set_additional_properties_false(x)
```

## Arguments

- x:

  List representing a JSON schema

## Value

List with additionalProperties set to false on every object
