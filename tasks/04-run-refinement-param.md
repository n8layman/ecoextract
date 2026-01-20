# Task: Update run_refinement Parameter

## Overview

Change `run_refinement` from boolean to support `FALSE`/`TRUE`/integer vector.

## Current State

- `run_refinement` is a boolean parameter in `process_documents()`
- `FALSE` = don't run refinement
- `TRUE` = run refinement on all documents

## Proposed Behavior

| Value            | Behavior                                             |
| ---------------- | ---------------------------------------------------- |
| `FALSE` (default) | Don't run refinement                                |
| `TRUE`           | Run refinement on ALL documents (that have records) |
| `integer vector` | Run refinement only on these specific `document_id`s |

## Implementation

### 1. Update check in workflow

```r
# Step 4: Refinement (opt-in, no skip logic)
records_exist <- (record_count > 0 for this document)
should_refine <- isTRUE(run_refinement) ||
                 (is.numeric(run_refinement) && document_id %in% run_refinement)

if (should_refine && records_exist) {
  refine_records(...)
}
```

### 2. Update parameter documentation

```r
#' @param run_refinement Controls refinement step. FALSE (default) skips refinement,
#'   TRUE runs on all documents with records, or an integer vector of document_ids
#'   to refine only specific documents.
```

### 3. Add validation

```r
if (!isFALSE(run_refinement) && !isTRUE(run_refinement) && !is.numeric(run_refinement)) {
  stop("run_refinement must be FALSE, TRUE, or an integer vector of document_ids")
}
```

## Why No force_reprocess_refinement?

Refinement is **opt-in only**. It doesn't use status-based skip logic, so there's nothing to "force". The `run_refinement` parameter itself controls whether refinement runs.

## Files to Modify

- `R/workflow.R`: Update `process_documents()` and `process_single_document()`

## Testing

- [ ] `run_refinement = FALSE` skips all refinement
- [ ] `run_refinement = TRUE` refines all documents with records
- [ ] `run_refinement = c(5L, 12L)` refines only those document_ids
- [ ] Documents with no records are skipped even when `run_refinement = TRUE`
- [ ] Invalid values throw error
