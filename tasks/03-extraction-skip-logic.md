# Task: Add Skip Logic to Extraction

## Overview

Extraction currently has NO skip logic - it always runs. Add status-only skip logic.

## Current State

- `extract_records()` has a `force_reprocess` parameter but it's **never used**
- `process_single_document()` hardcodes `force_reprocess = FALSE` at line ~346
- Extraction runs every time regardless of `extraction_status`

## Proposed Behavior

**Status-only check** (no data verification):
- If `extraction_status == "completed"` -> skip
- If `extraction_status != "completed"` (NULL, error, etc.) -> run
- Zero records is a valid extraction result, so don't check record count

## Implementation

### 1. Add `should_run_step_status_only()` helper

```r
#' Check if step should run (status-only, for Extraction)
#' @param status Current status value
#' @param force_param NULL, TRUE, or integer vector
#' @param document_id The document ID
#' @param upstream_ran Whether upstream step ran (triggers cascade)
#' @return logical
should_run_step_status_only <- function(status, force_param, document_id, upstream_ran) {
  if (is_forced(force_param, document_id) || upstream_ran) {
    return(TRUE)
  }
  if (is.null(status) || status != "completed") {
    return(TRUE)
  }
  return(FALSE)  # status == "completed" -> skip
}
```

### 2. Update workflow to use skip logic

In `process_single_document()`:

```r
# Step 3: Extraction (status-only check)
if (run_extraction &&
    should_run_step_status_only(extraction_status, force_reprocess_extraction, document_id, metadata_ran)) {
  # Run extraction
  extract_records(...)
}
```

### 3. Remove hardcoded FALSE

Remove/update the hardcoded `force_reprocess = FALSE` in workflow.

## Why Status-Only?

Zero records is a **valid result** from extraction. A document may simply have no extractable records matching the schema. Checking for `record_count > 0` would cause unnecessary re-runs.

## Files to Modify

- `R/workflow.R`: Add skip logic check before calling `extract_records()`
- `R/extraction.R`: Potentially remove unused `force_reprocess` param (or use it)

## Testing

- [ ] Document with `extraction_status = "completed"` is skipped
- [ ] Document with `extraction_status = NULL` runs extraction
- [ ] Document with `extraction_status = "error"` runs extraction
- [ ] Document with 0 records but `extraction_status = "completed"` is still skipped
- [ ] `force_reprocess_extraction = TRUE` forces re-extraction
