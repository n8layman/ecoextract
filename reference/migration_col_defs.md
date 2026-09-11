# Build column definition strings for migration DDL from PRAGMA table_info output

Build column definition strings for migration DDL from PRAGMA table_info
output

## Usage

``` r
migration_col_defs(info, overrides = list())
```

## Arguments

- info:

  Data frame from PRAGMA table_info

- overrides:

  Named list mapping column name to full definition string
