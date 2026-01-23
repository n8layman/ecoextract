# Task: Update run_refinement Parameter

## Overview

Change `run_refinement` from boolean to NULL/TRUE/integer vector. Refinement is opt-in only - no skip logic, just check if enabled and records exist.

## Current State

- `run_refinement` is a boolean parameter in `process_documents()`
- `FALSE` = don't run refinement
- `TRUE` = run refinement on all documents

## Proposed Behavior

| Value | Behavior |
| ----- | -------- |
| `NULL` (default) | Don't run refinement |
| `TRUE` | Run refinement on ALL documents with records |
| `integer vector` | Run refinement only on these specific `document_id`s |

## Implementation

### 1. Use `is_forced()` to check if refinement should run

```r
# Refinement - opt-in only, no skip logic
if (is_forced(run_refinement, doc_id) && records_exist) {
  refine_records(...)
}
```

### 2. Update parameter documentation

```r
#' @param run_refinement Controls refinement step. NULL (default) skips refinement,
#'   TRUE runs on all documents with records, or an integer vector of document_ids
#'   to refine only specific documents.
```

### 3. Add validation

```r
validate_force_param(run_refinement, "run_refinement")
```

## Why No Skip Logic for Refinement?

Refinement is opt-in. If `run_refinement` is set, run it. No status checking needed - user explicitly requested it.

## Files to Modify

- `R/workflow.R`: Update `process_documents()` and `process_single_document()`

## Testing

- [x] `run_refinement = NULL` skips all refinement
- [x] `run_refinement = TRUE` refines all documents with records
- [x] `run_refinement = c(5L, 12L)` refines only those document_ids
- [x] Documents with no records are skipped even when `run_refinement = TRUE`
- [x] Invalid values throw error
