# Calculate number of fields changed between original and refined records

Compares schema fields (excluding metadata) to count how many changed
during refinement.

## Usage

``` r
calculate_fields_changed(original_record, refined_record)
```

## Arguments

- original_record:

  Single row dataframe or named list of original record

- refined_record:

  Single row dataframe or named list of refined record

## Value

Integer count of fields that changed
