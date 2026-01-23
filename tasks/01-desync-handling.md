# Task: Desync Handling

## Overview

Desync detection is built into `should_run_step()` via the `data_exists` parameter.

## What is Desync?

A "desync" occurs when `status == "completed"` but the expected data is missing from the database. This can happen due to:
- Partial database restore
- Manual data deletion
- Bugs causing partial writes

## How It Works

`should_run_step(status, data_exists)` returns TRUE (run the step) if:
- `status` is NULL or not "completed", OR
- `status == "completed"` but `data_exists == FALSE`

## Data Existence Checks

| Step | `data_exists` Check |
| ---- | ------------------- |
| OCR | `document_content` not NULL/empty |
| Metadata | ALL of `title`, `author`, `year` exist |
| Extraction | `NULL` (no check - zero records is valid) |

```r
ocr_data_exists <- !is.null(doc$document_content) && nchar(doc$document_content) > 0

metadata_data_exists <- !is.null(doc$title) &&
                        !is.null(doc$first_author_lastname) &&
                        !is.null(doc$publication_year)
```

## Testing

- [ ] OCR desync: `ocr_status = "completed"` but `document_content = NULL` → re-runs
- [ ] Metadata desync: `metadata_status = "completed"` but `title = NULL` → re-runs
- [ ] Extraction: `extraction_status = "completed"` with 0 records → skips (valid state)
