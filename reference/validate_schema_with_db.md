# Validate schema compatibility with database (internal)

Validate schema compatibility with database (internal)

## Usage

``` r
validate_schema_with_db(db_conn, schema_json_list, table_name = "records")
```

## Arguments

- db_conn:

  Database connection

- schema_json_list:

  Parsed JSON schema as list

- table_name:

  Database table name to validate against

## Value

List with validation results
