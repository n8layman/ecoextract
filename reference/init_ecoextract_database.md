# Initialize EcoExtract database

Initialize EcoExtract database

## Usage

``` r
init_ecoextract_database(
  db_conn = "ecoextract_results.sqlite",
  schema_file = NULL,
  metadata_schema_file = NULL
)
```

## Arguments

- db_conn:

  Database connection (any DBI backend) or path to SQLite database file

- schema_file:

  Optional path to JSON schema file (determines record columns)

- metadata_schema_file:

  Optional path to metadata JSON schema file (adds documents columns for
  custom metadata fields)

## Value

NULL (creates database with required tables)
