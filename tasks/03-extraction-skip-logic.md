# Task: Add Skip Logic to Extraction

## Overview

Extraction currently has NO skip logic - it always runs. Add skip logic using `should_run_step()` with `data_exists = NULL` (no desync check since zero records is valid).

## Current State

- `extract_records()` has a `force_reprocess` parameter but it's **never used**
- `process_single_document()` hardcodes `force_reprocess = FALSE`
- Extraction runs every time regardless of `extraction_status`

## Proposed Behavior

- If `extraction_status == "completed"` → skip
- If `extraction_status != "completed"` (NULL, error, etc.) → run
- Zero records is valid - no desync check needed

## Implementation

```r
# Extraction - no desync check (zero records valid)
if (run_extraction && should_run_step(extraction_status, NULL)) {
  extract_records(...)
}
```

## Files to Modify

- `R/workflow.R`: Add skip logic before calling `extract_records()`
- `R/extraction.R`: Remove unused `force_reprocess` param

## Testing

- [x] Document with `extraction_status = "completed"` is skipped
- [x] Document with `extraction_status = NULL` runs extraction
- [x] Document with `extraction_status = "error"` runs extraction
- [x] Document with 0 records but `extraction_status = "completed"` is still skipped
- [x] Cascade: metadata runs → extraction_status nullified → extraction runs
