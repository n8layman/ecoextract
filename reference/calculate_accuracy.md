# Calculate extraction accuracy metrics from verified documents

Computes field-level accuracy and record detection metrics from
human-reviewed documents. Only includes records from documents that have
been reviewed (reviewed_at IS NOT NULL).

## Usage

``` r
calculate_accuracy(db_conn, document_ids = NULL, schema_file = NULL)
```

## Arguments

- db_conn:

  Database connection or path to database file

- document_ids:

  Optional vector of document IDs to include (default: all verified)

- schema_file:

  Optional path to schema JSON file (uses default if NULL)

## Value

List with accuracy metrics:

Raw counts: - verified_documents: count of reviewed documents -
verified_records: total records in verified documents - model_extracted:
records extracted by model - human_added: records added by humans (model
missed) - deleted: records deleted by humans (hallucinated) -
records_with_edits: records with at least one field edit - column_edits:
named vector of edit counts per column

Field-level metrics (accuracy of individual fields): - total_fields:
total fields model extracted - correct_fields: fields that were
correct - field_precision: correct_fields / total_fields - field_recall:
correct_fields / all_true_fields - field_f1: harmonic mean of field
precision and recall

Record detection metrics (finding records): - records_found: records
model found (includes imperfect extractions) - records_missed: records
model failed to find - records_hallucinated: records model made up -
detection_precision: records_found / model_extracted - detection_recall:
records_found / total_true_records - perfect_record_rate: of found
records, how many had zero errors

Per-column accuracy: - column_accuracy: named vector of per-column
accuracy (1 - edits/model_extracted)

Edit severity (based on unique/required fields from schema): -
major_edits: count of edits to unique or required fields - minor_edits:
count of edits to other fields - major_edit_rate: major_edits /
total_edits - avg_edits_per_document: mean edits per verified document

## Details

Separates two questions: 1. Record detection: Did the model find the
record vs hallucinate vs miss it? 2. Field accuracy: Of the fields
extracted, how many were correct?

Edit severity is classified based on schema: - Major edits: Changes to
unique fields (x-unique-fields) or required fields - Minor edits:
Changes to optional descriptive fields
