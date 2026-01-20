# Task: Desync Handling (OCR and Metadata only)

## Overview

Add detection and handling for status/data mismatches in OCR and Metadata steps.

## What is Desync?

A "desync" occurs when `status == "completed"` but the expected data is missing from the database. This can happen due to:
- Partial database restore
- Manual data deletion
- Bugs causing partial writes

## Affected Steps

| Step     | Data Check                                                                 |
| -------- | -------------------------------------------------------------------------- |
| OCR      | `document_content IS NOT NULL AND document_content != ''`                  |
| Metadata | `title IS NOT NULL OR first_author_lastname IS NOT NULL OR publication_year IS NOT NULL` |

**Not applicable to:**
- Extraction (status-only check; zero records is valid)
- Refinement (opt-in only, no status-based skip logic)

## Implementation

### Behavior

If `status == "completed"` but data is missing:
1. Set status to `"Error: Status was completed but no data found in DB"`
2. Re-run the step (treat as if status was NULL)

### Where to Implement

In `should_run_step()` helper function (to be created in `R/workflow.R` or `R/utils.R`):

```r
should_run_step <- function(status, data_exists, force_param, document_id, upstream_ran) {
  if (is_forced(force_param, document_id) || upstream_ran) {
    return(TRUE)
  }
  if (is.null(status) || status != "completed") {
    return(TRUE)
  }
  if (status == "completed" && !data_exists) {
    # Desync detected - will need to update status in DB
    return(TRUE)
  }
  return(FALSE)  # status == "completed" AND data exists -> skip
}
```

### Status Update

When desync is detected, update the document's status column before re-running:

```r
if (status == "completed" && !data_exists) {
  update_document_status(
    conn,
    document_id,
    status_column,
    "Error: Status was completed but no data found in DB"
  )
}
```

## Testing

- [ ] Test OCR desync: Set `ocr_status = "completed"` but `document_content = NULL`
- [ ] Test Metadata desync: Set `metadata_status = "completed"` but all ID fields NULL
- [ ] Verify error status is written before re-run
- [ ] Verify step re-runs after desync detection
