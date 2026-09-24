# Text form of a document field value for edit comparison (internal)

NULL, NA, and empty strings all mean "no value", so a reviewer saving an
empty input over a missing value does not count as an edit.

## Usage

``` r
field_value_text(value)
```

## Arguments

- value:

  Field value

## Value

Character string, or NA_character\_ for no value
