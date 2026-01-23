# Task: Cascade via Status Nullification

## Overview

Cascade is handled by nullifying the immediate downstream status when a step runs. No tracking flags needed.

## Cascade Rules

| When This Runs | Nullify This |
| -------------- | ------------ |
| OCR | `metadata_status` |
| Metadata | `extraction_status` |
| Extraction | (nothing) |

## Implementation

```r
# OCR
if (should_run_step(ocr_status, ocr_data_exists)) {
  run_ocr(...)
  set_status(conn, doc_id, "metadata_status", NULL)  # cascade
}

# Metadata
if (should_run_step(metadata_status, metadata_data_exists)) {
  extract_metadata(...)
  set_status(conn, doc_id, "extraction_status", NULL)  # cascade
}

# Extraction
if (run_extraction && should_run_step(extraction_status, NULL)) {
  extract_records(...)
  # No cascade - extraction doesn't delete records, just adds new ones
}

# Refinement - opt-in only
if (is_forced(run_refinement, doc_id) && records_exist) {
  refine_records(...)
}
```

## How Cascade Propagates

Example: `force_reprocess_ocr = TRUE` for doc_id 5

1. At workflow start: `ocr_status` set to NULL
2. OCR runs (status was NULL) → sets `metadata_status` to NULL
3. Metadata runs (status was NULL) → sets `extraction_status` to NULL
4. Extraction runs (status was NULL)

Each step nullifies only its immediate downstream. Cascade propagates naturally.

## Why Not Delete Records on Extraction Re-run?

Extraction uses deduplication - it won't add duplicate records. Old records remain (potentially stale from old OCR), new records get added. Deleting records is destructive and should be a human decision.

## Files to Modify

- `R/workflow.R`: Add status nullification after each step runs

## Testing

- [x] OCR run nullifies `metadata_status`
- [x] Metadata run nullifies `extraction_status`
- [x] Extraction run does NOT nullify anything
- [x] Full cascade: force OCR → metadata runs → extraction runs
