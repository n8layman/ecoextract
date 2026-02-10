# Save records to EcoExtract database (internal)

Save records to EcoExtract database (internal)

## Usage

``` r
save_records_to_db(
  db_path,
  document_id,
  interactions_df,
  metadata = list(),
  schema_list = NULL,
  mode = "insert"
)
```

## Arguments

- db_path:

  Path to database file

- document_id:

  Document ID

- interactions_df:

  Dataframe of records

- metadata:

  Processing metadata

- schema_list:

  Optional parsed JSON schema for array normalization

## Value

TRUE if successful
