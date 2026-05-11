# Scrub pipeline stages beyond a cutoff from a database

Scrub pipeline stages beyond a cutoff from a database

## Usage

``` r
scrub_pipeline_stages(db_path, through)
```

## Arguments

- db_path:

  Path to SQLite database to modify in place

- through:

  Pipeline stage to preserve ("ocr", "metadata", "extraction")

## Value

NULL (modifies database in place)
