# Task: Update OCR/Metadata to Status-First Skip Logic

## Overview

Change OCR and Metadata from data-first to status-first skip logic.

## Current State

### OCR (`R/ocr.R`)
- **Data-first**: Checks if `document_content` exists
- Runs if content is missing, regardless of status

### Metadata (`R/metadata.R`)
- **Data-first**: Checks if `title`, `first_author_lastname`, or `publication_year` exist
- Runs if all are missing, regardless of status

## Proposed Behavior

### Status-First Check

1. First check `status == "completed"`
2. If completed, verify data exists (desync check)
3. If desync detected, set error status and re-run
4. If status not completed, run the step

## Implementation

### `should_run_step()` helper

```r
should_run_step <- function(status, data_exists, force_param, document_id, upstream_ran) {
  # Forced or cascaded - always run
  if (is_forced(force_param, document_id) || upstream_ran) {
    return(TRUE)
  }

  # Status not completed - run
  if (is.null(status) || status != "completed") {
    return(TRUE)
  }

  # Status completed but data missing (desync) - run
  if (status == "completed" && !data_exists) {
    return(TRUE)
  }

  # Status completed and data exists - skip
  return(FALSE)
}
```

### Data existence checks

```r
# OCR
ocr_data_exists <- !is.null(doc$document_content) &&
                   nchar(doc$document_content) > 0

# Metadata
metadata_data_exists <- !is.null(doc$title) ||
                        !is.null(doc$first_author_lastname) ||
                        !is.null(doc$publication_year)
```

## Why Status-First?

- **Consistency**: All steps use status as primary indicator
- **Explicit state**: Status column clearly shows step completion
- **Desync detection**: Can catch and log data/status mismatches
- **Simpler logic**: Check one column first, then verify if needed

## Files to Modify

- `R/workflow.R`: Update skip logic in `process_single_document()`
- `R/ocr.R`: May need to remove internal skip logic (let workflow handle it)
- `R/metadata.R`: May need to remove internal skip logic (let workflow handle it)

## Testing

- [ ] OCR with `ocr_status = "completed"` and content present -> skipped
- [ ] OCR with `ocr_status = NULL` -> runs
- [ ] OCR with `ocr_status = "completed"` but no content -> desync handled
- [ ] Same tests for Metadata
- [ ] Force parameters override status check
- [ ] Upstream cascade overrides status check
