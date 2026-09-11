# Build a record ID prefix from a document's identifier values (internal)

Joins the values of the metadata fields named in `x-record-id-fields`,
each stripped to letters and digits, followed by the replicate number.
Missing or empty values become "Unknown". For the default metadata
schema this gives "Author_Year_1".

## Usage

``` r
build_record_id_prefix(id_values)
```

## Arguments

- id_values:

  List of identifier values, in `x-record-id-fields` order

## Value

Character record ID prefix
