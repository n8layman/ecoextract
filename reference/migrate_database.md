# Migrate database schema for existing databases

Adds new columns and tables required by schema updates. Safe to run
multiple times - only adds missing elements.

## Usage

``` r
migrate_database(con)
```

## Arguments

- con:

  Database connection

## Value

NULL (invisibly)
