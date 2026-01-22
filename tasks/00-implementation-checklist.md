# Skip/Cascade Logic Implementation Checklist

## Overview

This checklist tracks the implementation of skip and cascade logic for the document processing pipeline.

## Implementation Order

### Phase 1: Foundation

- [ ] **Task 1: Create `is_forced()` helper** - [02-force-reprocess-params.md](02-force-reprocess-params.md)
- [ ] **Task 2: Create `should_run_step()` helper** - [06-status-first-skip.md](06-status-first-skip.md)

### Phase 2: Parameter Updates

- [ ] **Task 3: Update `force_reprocess_*` parameters** - [02-force-reprocess-params.md](02-force-reprocess-params.md)
- [ ] **Task 4: Update `run_refinement` parameter** - [04-run-refinement-param.md](04-run-refinement-param.md)

### Phase 3: Wire Up Skip Logic

- [ ] **Task 5: Implement skip logic and cascade** - [03-extraction-skip-logic.md](03-extraction-skip-logic.md), [05-cascade-tracking.md](05-cascade-tracking.md)

### Phase 4: Testing

- [ ] Test `is_forced()` with NULL, TRUE, integer vector
- [ ] Test `should_run_step()` with status/data_exists combinations
- [ ] Test desync detection
- [ ] Test cascade via status nullification
- [ ] Test `run_refinement` with NULL, TRUE, integer vector

## Core Design

### `is_forced()` - Check if document should be forced/included

```r
is_forced <- function(force_param, document_id) {
  if (is.null(force_param)) return(FALSE)
  if (isTRUE(force_param)) return(TRUE)
  if (is.numeric(force_param)) return(document_id %in% force_param)
  return(FALSE)
}
```

### `should_run_step()` - Unified skip logic (OCR, Metadata, Extraction only)

```r
should_run_step <- function(status, data_exists) {
  if (is.null(status) || status != "completed") return(TRUE)
  if (!is.null(data_exists) && !data_exists) return(TRUE)  # desync
  return(FALSE)
}
```

### Full workflow

```r
# At workflow start - nullify statuses for forced documents
if (is_forced(force_reprocess_ocr, doc_id)) {
  set_status(conn, doc_id, "ocr_status", NULL)
}
if (is_forced(force_reprocess_metadata, doc_id)) {
  set_status(conn, doc_id, "metadata_status", NULL)
}
if (is_forced(force_reprocess_extraction, doc_id)) {
  set_status(conn, doc_id, "extraction_status", NULL)
}

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
}

# Refinement - opt-in only, no skip logic
if (is_forced(run_refinement, doc_id) && records_exist) {
  refine_records(...)
}
```

### Data existence checks

```r
ocr_data_exists <- !is.null(doc$document_content) && nchar(doc$document_content) > 0
metadata_data_exists <- !is.null(doc$title) && !is.null(doc$first_author_lastname) && !is.null(doc$publication_year)
records_exist <- DBI::dbGetQuery(conn, "SELECT COUNT(*) > 0 FROM records WHERE document_id = ?", list(doc_id))[[1]]
```

## Files to Modify

| File | Changes |
| ---- | ------- |
| `R/workflow.R` | `is_forced()`, `should_run_step()`, status nullification, skip logic |
| `R/ocr.R` | Remove internal skip logic |
| `R/metadata.R` | Remove internal skip logic |
| `R/extraction.R` | Remove unused `force_reprocess` param |

## Task File Reference

| # | Task | File |
| - | ---- | ---- |
| 1 | `is_forced()` helper | [02-force-reprocess-params.md](02-force-reprocess-params.md) |
| 2 | `should_run_step()` helper | [06-status-first-skip.md](06-status-first-skip.md) |
| 3 | `force_reprocess_*` params | [02-force-reprocess-params.md](02-force-reprocess-params.md) |
| 4 | `run_refinement` param | [04-run-refinement-param.md](04-run-refinement-param.md) |
| 5 | Skip logic and cascade | [03-extraction-skip-logic.md](03-extraction-skip-logic.md), [05-cascade-tracking.md](05-cascade-tracking.md) |
