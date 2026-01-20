# Task: Update force_reprocess Parameters

## Overview

Change all `force_reprocess_*` parameters from boolean to support `NULL`/`TRUE`/integer vector.

## Current State

| Parameter                  | Current Type | Location           |
| -------------------------- | ------------ | ------------------ |
| `force_reprocess_ocr`      | logical      | `process_documents()` |
| `force_reprocess_metadata` | logical      | `process_documents()` |
| `force_reprocess` (extraction) | logical  | `extract_records()` (unused) |

**Missing**: `force_reprocess_extraction` parameter in `process_documents()`

## Proposed Behavior

| Value            | Behavior                                           |
| ---------------- | -------------------------------------------------- |
| `NULL` (default) | No forcing, use normal skip logic                  |
| `TRUE`           | Force reprocess ALL documents                      |
| `integer vector` | Force reprocess only these specific `document_id`s |

## Implementation

### 1. Add `is_forced()` helper

```r
#' Check if a document should be forced to reprocess
#' @param force_param NULL, TRUE, or integer vector of document_ids
#' @param document_id The document ID to check
#' @return logical
is_forced <- function(force_param, document_id) {
  if (is.null(force_param)) return(FALSE)
  if (isTRUE(force_param)) return(TRUE)
  if (is.numeric(force_param)) return(document_id %in% force_param)
  return(FALSE)
}
```

### 2. Update `process_documents()` signature

```r
process_documents <- function(
  ...,
  force_reprocess_ocr = NULL,
  force_reprocess_metadata = NULL,
  force_reprocess_extraction = NULL,  # NEW
  ...
)
```

### 3. Update parameter validation

Add validation that force_reprocess params are NULL, TRUE, or integer vector:

```r
validate_force_param <- function(param, param_name) {
  if (!is.null(param) && !isTRUE(param) && !is.numeric(param)) {
    stop(sprintf("%s must be NULL, TRUE, or an integer vector of document_ids", param_name))
  }
}
```

### 4. Pass parameters to `process_single_document()`

Ensure force parameters are passed down and used in skip logic.

## Files to Modify

- `R/workflow.R`: `process_documents()`, `process_single_document()`
- `R/extraction.R`: Remove unused `force_reprocess` param or update to use it

## Testing

- [ ] `force_reprocess_ocr = NULL` uses normal skip logic
- [ ] `force_reprocess_ocr = TRUE` forces all documents
- [ ] `force_reprocess_ocr = c(5L, 12L)` forces only those document_ids
- [ ] Same tests for metadata and extraction
- [ ] Invalid values (e.g., `"yes"`) throw error
