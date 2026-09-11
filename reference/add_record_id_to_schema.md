# Declare record_id in a records schema for refinement (internal)

Refinement must return each record's `record_id` so edits map back to
existing rows. `record_id` is a system field and not part of project
schemas, and with `additionalProperties: false` the model cannot add
undeclared fields, so it is added here as a required string.

## Usage

``` r
add_record_id_to_schema(schema_list)
```

## Arguments

- schema_list:

  Parsed records JSON schema

## Value

Schema list with record_id added to the record properties and required
fields
