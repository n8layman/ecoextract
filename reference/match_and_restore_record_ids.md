# Restore id and record_id from existing records after LLM refinement

Restore id and record_id from existing records after LLM refinement

## Usage

``` r
match_and_restore_record_ids(refined_records, existing_records)
```

## Arguments

- refined_records:

  Dataframe of records from LLM refinement

- existing_records:

  Dataframe of existing records from database (must include id)

## Value

Dataframe with id restored via join on record_id
