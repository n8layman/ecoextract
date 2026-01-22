# Task: Create `should_run_step()` Helper

## Overview

Create a simple `should_run_step()` function for skip logic. Used by OCR, Metadata, and Extraction only. Refinement is opt-in and doesn't use this.

## Function Design

```r
#' Determine if a processing step should run
#' @param status Current status value for this step
#' @param data_exists Logical or NULL. If logical, checks for desync.
#'   Pass NULL to skip desync check (e.g., for Extraction where zero records is valid).
#' @return logical - TRUE if step should run, FALSE to skip
should_run_step <- function(status, data_exists) {
  # Status not completed - needs to run
  if (is.null(status) || status != "completed") return(TRUE)

  # Desync check - status says completed but data is missing
  if (!is.null(data_exists) && !data_exists) return(TRUE)

  # Status completed and data exists (or no check needed) - skip
  return(FALSE)
}
```

## Usage

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

# Extraction - no desync check (zero records valid)
if (run_extraction && should_run_step(extraction_status, NULL)) {
  extract_records(...)
}

# Refinement - opt-in only, doesn't use should_run_step()
if (is_forced(run_refinement, doc_id) && records_exist) {
  refine_records(...)
}
```

## Data Existence Checks

```r
ocr_data_exists <- !is.null(doc$document_content) && nchar(doc$document_content) > 0

metadata_data_exists <- !is.null(doc$title) &&
                        !is.null(doc$first_author_lastname) &&
                        !is.null(doc$publication_year)

records_exist <- DBI::dbGetQuery(
  conn,
  "SELECT COUNT(*) > 0 FROM records WHERE document_id = ?",
  list(doc_id)
)[[1]]
```

## Files to Modify

- `R/workflow.R`: Add `should_run_step()`

## Testing

- [x] `status = NULL` -> runs
- [x] `status = "completed"` with `data_exists = TRUE` -> skips
- [x] `status = "completed"` with `data_exists = FALSE` -> runs (desync)
- [x] `status = "completed"` with `data_exists = NULL` -> skips (no desync check)
- [x] `status = "error"` -> runs
