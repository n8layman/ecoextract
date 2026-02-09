# Understanding Accuracy Metrics in EcoExtract

## Overview

EcoExtract calculates accuracy by analyzing human edits to model-extracted records. When you review documents using [ecoreview](https://github.com/n8layman/ecoreview), all edits are tracked in an audit table (`record_edits`). The `calculate_accuracy()` function analyzes these edits to provide comprehensive accuracy metrics.

## Philosophy: Two Separate Questions

Traditional accuracy metrics treat extraction as all-or-nothing: a record is either "correct" or "incorrect." But in practice, extraction quality has two independent dimensions:

1. **Record Detection**: Did the model find the record, or did it miss it? Did it hallucinate records that don't exist?
2. **Field Accuracy**: Of the records the model found, how accurate were the individual fields?

EcoExtract separates these concerns to give you a more nuanced understanding of model performance.

## Core Concepts

### Ground Truth

Ground truth is established through human review:
- **Model extractions** (records with `added_by_user = 0` or NULL)
- **Human additions** (records with `added_by_user = 1`) indicate records the model missed
- **Soft deletes** (records with `deleted_by_user` set) indicate hallucinations
- **Field edits** (tracked in `record_edits` table) indicate which specific fields were wrong

Only documents marked as reviewed (`reviewed_at IS NOT NULL`) are included in accuracy calculations.

### Verified Documents

Accuracy is only calculated for documents that have been human-reviewed. This ensures metrics reflect actual human judgment rather than unverified model output.

## Metrics Explained

### Raw Counts

These are the fundamental measurements from which all other metrics derive:

- **verified_documents**: Number of documents that have been reviewed
- **verified_records**: Total records across all verified documents
- **model_extracted**: Records the model extracted (may include hallucinations)
- **human_added**: Records humans added because model missed them (false negatives)
- **deleted**: Records humans soft-deleted because model hallucinated them (false positives)
- **records_with_edits**: Records that had at least one field corrected
- **column_edits**: Count of edits per column (named vector)

### Record Detection Metrics

These answer: "Did the model find the records?"

#### Records Classification
- **records_found**: `model_extracted - deleted`
  - True positives: Records the model found (even if imperfect)
- **records_missed**: `human_added`
  - False negatives: Records that exist but model didn't find
- **records_hallucinated**: `deleted`
  - False positives: Records model made up that don't exist

#### Detection Performance
- **detection_precision**: `records_found / model_extracted`
  - Of everything the model extracted, what fraction was real (not hallucinated)?
  - High precision means few hallucinations

- **detection_recall**: `records_found / (records_found + records_missed)`
  - Of all true records, what fraction did the model find?
  - High recall means few missed records

- **perfect_record_rate**: `(records_found - records_with_edits) / records_found`
  - Of records the model found, what fraction had zero errors?
  - Measures extraction quality for found records

### Field-Level Metrics

These answer: "How accurate were the individual fields?"

Field-level metrics provide partial credit. If a record has 10 fields and the model got 9 correct, it's credited with 9 correct fields rather than being treated as completely wrong.

#### Field Calculations
- **total_fields**: `model_extracted × num_fields`
  - Total fields the model attempted to extract

- **correct_fields**: `total_fields - deleted_fields - edited_fields`
  - Fields that were extracted correctly
  - deleted_fields = `deleted × num_fields` (all fields in deleted records are wrong)
  - edited_fields = `sum(column_edits)` (fields that humans corrected)

#### Field Performance
- **field_precision**: `correct_fields / total_fields`
  - Of all fields the model extracted, what fraction was correct?

- **field_recall**: `correct_fields / true_fields`
  - true_fields = `(records_found × num_fields) + (human_added × num_fields)`
  - Of all true fields that should exist, what fraction did we extract correctly?

- **field_f1**: Harmonic mean of field precision and recall
  - `2 × precision × recall / (precision + recall)`
  - Balanced measure combining both metrics

### Per-Column Accuracy

- **column_accuracy**: Named vector showing accuracy for each column
  - Formula: `1 - (column_edits / model_extracted)`
  - Example: If 100 records extracted and "species" field edited 15 times, species accuracy = 0.85
  - Shows which fields are hardest for the model to extract
  - Helps identify where to improve prompts or schemas

### Edit Severity Metrics

Not all edits are equal. EcoExtract classifies edits based on the schema:

#### Major vs Minor Edits

**Major edits** affect fields that identify or are required for the record:
- **Unique fields** (`x-unique-fields` in schema): Fields that identify the record
  - Example: species names, dates, locations that distinguish one record from another
- **Required fields** (`required` in schema): Fields mandatory for record validity
  - Example: supporting sentences, organisms_identifiable

**Minor edits** affect optional descriptive fields:
- Fields that provide additional detail but aren't core to record identity
- Example: publication_year, page_number

#### Severity Metrics
- **major_edits**: Count of edits to unique or required fields
- **minor_edits**: Count of edits to other fields
- **major_edit_rate**: `major_edits / (major_edits + minor_edits)`
  - Closer to 1.0 means most errors are in critical fields
  - Closer to 0.0 means most errors are in minor details
- **avg_edits_per_document**: `total_edits / verified_documents`
  - On average, how many field corrections per document?
  - Lower is better

## Example Scenario

Say you review a document with **10 true records**:

**Model Performance:**
- Extracts 12 records
  - 7 are perfect (no edits needed)
  - 1 has 2 minor field edits
  - 1 has 1 major field edit (wrong species name)
  - 1 is missing (you add it)
  - 2 are hallucinations (you delete them)

**Each record has 8 fields total:**
- 4 unique fields (species names, dates)
- 2 required fields (supporting sentences)
- 2 optional fields (page number, publication year)

### Calculated Metrics

**Raw Counts:**
- model_extracted = 12
- human_added = 1
- deleted = 2
- records_with_edits = 2
- total_edits = 3 (2 minor + 1 major)

**Record Detection:**
- records_found = 12 - 2 = 10
- records_missed = 1
- records_hallucinated = 2
- detection_precision = 10/12 = 0.833 (83.3%)
- detection_recall = 10/11 = 0.909 (90.9%)
- perfect_record_rate = 7/10 = 0.70 (70%)

**Field-Level:**
- total_fields = 12 × 8 = 96 fields attempted
- deleted_fields = 2 × 8 = 16 fields (in hallucinated records)
- edited_fields = 3 fields corrected
- correct_fields = 96 - 16 - 3 = 77 fields
- field_precision = 77/96 = 0.802 (80.2%)
- true_fields = (10 × 8) + (1 × 8) = 88 fields should exist
- field_recall = 77/88 = 0.875 (87.5%)

**Edit Severity:**
- major_edits = 1 (the species name)
- minor_edits = 2 (the two optional field edits)
- major_edit_rate = 1/3 = 0.333 (33.3% of errors are major)
- avg_edits_per_document = 3/1 = 3.0

### Interpretation

This model:
- **Good detection**: Found 91% of records, only hallucinated 17%
- **Decent extraction**: 80% of fields correct, giving partial credit for mostly-correct records
- **Room for improvement**: 30% of found records need corrections
- **Encouraging error profile**: Only 33% of errors are in critical identifying fields

## Usage

```r
library(ecoextract)

# Calculate accuracy for all verified documents
accuracy <- calculate_accuracy("my_database.db")

# View key metrics
accuracy$detection_recall    # Did we find the records?
accuracy$field_precision     # How accurate were the fields?
accuracy$major_edit_rate     # How serious were the errors?

# Calculate accuracy for specific documents
accuracy <- calculate_accuracy("my_database.db", document_ids = c(1, 2, 3))

# Use custom schema location
accuracy <- calculate_accuracy("my_database.db", schema_file = "custom_schema.json")
```

## Visualizing Accuracy

Accuracy visualizations (confusion matrices, field accuracy heatmaps) are available in the [ecoreview](https://github.com/n8layman/ecoreview) Shiny app, which provides an interactive interface for reviewing extractions and viewing accuracy metrics.

## Design Decisions

### Why Field-Level Instead of Record-Level?

**Problem with record-level:** A record with 1 wrong field out of 10 is treated the same as a completely wrong record (0% vs 90% correct).

**Field-level solution:** Gives partial credit. The 90%-correct record contributes 9 correct fields and 1 incorrect field to the metrics.

This is more informative and better reflects the actual quality of extraction.

### Why Separate Detection from Accuracy?

Finding a record is different from extracting it correctly:
- A model might find all records but extract many fields incorrectly (high recall, low field precision)
- A model might only extract records it's very confident about (low recall, high field precision)

Separating these dimensions helps diagnose where to improve.

### Why Classify Edit Severity?

Not all errors matter equally:
- Wrong species name: Fundamentally changes what the record represents (major)
- Wrong page number: Minor detail that doesn't affect the science (minor)

Understanding error severity helps prioritize improvements.

### Why Average Edits Per Document?

This gives a sense of overall quality across the corpus:
- avg_edits_per_document = 2: Model is quite accurate, minor cleanup needed
- avg_edits_per_document = 50: Model needs significant improvement

## Technical Notes

### Assumptions
- All records have the same number of fields (defined by schema)
- Nullable fields still count as fields for accuracy calculation
- Edit severity requires schema with `x-unique-fields` and `required` specifications

### Limitations
- No distinction between "empty → filled" vs "wrong → corrected" edits
- Treats all edits within a severity class equally (no weighting by importance)
- Assumes schema accurately reflects field importance via unique/required flags

### Future Enhancements
Could add:
- Edit type classification (addition vs correction vs deletion)
- Per-document accuracy variance
- Temporal trends (accuracy over time)
- Confidence intervals for small sample sizes

## Related Documentation

- [ecoreview README](https://github.com/n8layman/ecoreview) - Review and edit records
- [SCHEMA_GUIDE.md](ecoextract/SCHEMA_GUIDE.md) - Define custom schemas
- [Vignette](vignettes/ecoextract-workflow.Rmd) - Complete workflow tutorial

## Questions?

Open an issue on [GitHub](https://github.com/n8layman/ecoextract/issues).
