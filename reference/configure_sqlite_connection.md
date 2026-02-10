# Database Functions for EcoExtract Package

Standalone database operations for ecological interaction storage
Configure SQLite connection for optimal concurrency

## Usage

``` r
configure_sqlite_connection(con)
```

## Arguments

- con:

  SQLite database connection

## Value

The connection object (invisibly)

## Details

Sets PRAGMA options to prevent database locked errors and enable
Write-Ahead Logging (WAL) for better concurrent access.
