# Add token usage columns to the documents table (internal)

Adds the per-step token usage columns that are not already in the
documents table, so databases created before token tracking gain them.
Rows processed before then keep NULL.

## Usage

``` r
add_usage_columns(con)
```

## Arguments

- con:

  Database connection

## Value

NULL (invisibly)
