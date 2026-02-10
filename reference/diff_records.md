# Diff Records Between Original and Edited Versions

Compares two record dataframes and categorizes changes by id (surrogate
key). Uses id for stable identification since record_id is a mutable
business identifier.

## Usage

``` r
diff_records(original_df, records_df)
```

## Arguments

- original_df:

  Original records dataframe (before edits)

- records_df:

  Edited records dataframe (after edits)

## Value

List with: \$modified (ids), \$added (dataframe), \$deleted (ids)
