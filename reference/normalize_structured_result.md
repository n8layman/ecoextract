# Normalize raw structured output from chat_structured(convert = FALSE)

When using `convert = FALSE`, the raw result may be a parsed list
(TypeObject without envelope), a list with a `data` string element
(data-string envelope), or a bare character string. This function
normalizes all cases to a parsed list.

## Usage

``` r
normalize_structured_result(raw)
```

## Arguments

- raw:

  Raw result from chat_structured(convert = FALSE)

## Value

Parsed list
