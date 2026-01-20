# Task: Add Cascade Tracking

## Overview

When an upstream step runs, downstream steps should re-run. Track which steps ran and use that to trigger cascade.

## Cascade Rules

| If This Runs | These Become Stale |
| ------------ | ------------------ |
| OCR          | Metadata, Extraction |
| Metadata     | Extraction         |
| Extraction   | (nothing)          |
| Refinement   | (nothing)          |

## Implementation

### 1. Add tracking flags in `process_single_document()`

```r
# Track what actually ran (for cascade)
ocr_ran <- FALSE
metadata_ran <- FALSE
# Note: extraction_ran not needed - extraction doesn't cascade to anything
```

### 2. Set flags when steps run

```r
# Step 1: OCR
if (should_run_step(ocr_status, ocr_data_exists, force_reprocess_ocr, document_id, FALSE)) {
  run_ocr(...)
  ocr_ran <- TRUE
}

# Step 2: Metadata
if (should_run_step(metadata_status, metadata_data_exists, force_reprocess_metadata, document_id, ocr_ran)) {
  extract_metadata(...)
  metadata_ran <- TRUE
}

# Step 3: Extraction
if (run_extraction &&
    should_run_step_status_only(extraction_status, force_reprocess_extraction, document_id, metadata_ran)) {
  extract_records(...)
}
```

### 3. Pass `upstream_ran` to skip logic helpers

The `should_run_step()` and `should_run_step_status_only()` helpers accept an `upstream_ran` parameter. When `TRUE`, the step runs regardless of status.

## Status Nullification

When forcing a step via `force_reprocess_*`, also nullify downstream status columns to ensure cascade:

| Force Parameter              | Sets to NULL                           |
| ---------------------------- | -------------------------------------- |
| `force_reprocess_ocr`        | `metadata_status`, `extraction_status` |
| `force_reprocess_metadata`   | `extraction_status`                    |
| `force_reprocess_extraction` | (nothing)                              |

### Implementation

At the start of processing (or before each document), if force is set:

```r
if (is_forced(force_reprocess_ocr, document_id)) {
  # Nullify downstream statuses
  update_document_status(conn, document_id, "metadata_status", NULL)
  update_document_status(conn, document_id, "extraction_status", NULL)
}

if (is_forced(force_reprocess_metadata, document_id)) {
  update_document_status(conn, document_id, "extraction_status", NULL)
}
```

## Files to Modify

- `R/workflow.R`: `process_single_document()`

## Testing

- [ ] OCR re-run triggers metadata re-run
- [ ] OCR re-run triggers extraction re-run
- [ ] Metadata re-run triggers extraction re-run
- [ ] Extraction re-run does NOT trigger refinement (refinement is opt-in)
- [ ] `force_reprocess_ocr` nullifies metadata and extraction statuses
- [ ] `force_reprocess_metadata` nullifies extraction status only
- [ ] Cascade only affects forced document_ids when using integer vector
