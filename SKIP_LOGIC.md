# Skip and Cascade Logic for Document Processing

## Overview

Each pipeline step should be skippable if its output already exists in the database. When a step is re-run (forced or due to upstream changes), downstream steps become stale and must also re-run.

## Pipeline Steps

```
OCR → Metadata → Extraction → Refinement
```

## Skip Conditions (Default Behavior)

Skip logic uses a two-step check for OCR and Metadata:

1. Check if status == "completed"
2. If yes, verify data actually exists in DB
3. If either test fails, re-run step

**Exceptions**:

- **Extraction**: Status-only check (zero records is a valid result)
- **Refinement**: Opt-in only, no skip logic (controlled by `run_refinement` parameter)

| Step       | Status Column                     | Data Verification                                                                                                                     |
| ---------- | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| OCR        | `ocr_status`                      | `document_content IS NOT NULL AND document_content != ''`                                                                             |
| Metadata   | `metadata_status`                 | `title IS NOT NULL OR first_author_lastname IS NOT NULL OR publication_year IS NOT NULL` (key ID fields; `authors` array is separate) |
| Extraction | `extraction_status`               | N/A (status-only; zero records is valid)                                                                                              |
| Refinement | N/A (opt-in via `run_refinement`) | Records must exist to refine                                                                                                          |

### Data/Status Desync Handling (OCR and Metadata only)

A "desync" is when the status column says "completed" but data is missing from the database (e.g., due to partial restore, manual deletion, or bugs).

If `status == "completed"` but data is missing:

- Set status to `"Error: Status was completed but no data found in DB"`
- Re-run the step (treat as if status was NULL)

**Note**: Does not apply to Extraction (status-only) or Refinement (opt-in only).

## Cascade Rules

When a step runs (either forced or because data is missing), downstream steps become stale:

| If This Runs | These Become Stale                             |
| ------------ | ---------------------------------------------- |
| OCR          | Metadata, Extraction                           |
| Metadata     | Extraction                                     |
| Extraction   | (nothing - refinement is opt-in, not cascaded) |
| Refinement   | (nothing)                                      |

**Note**: Refinement is not part of the cascade because it's opt-in via `run_refinement` and doesn't use status-based skip logic.

## Force Reprocess Parameters

Each `force_reprocess_*` parameter accepts:

| Value            | Behavior                                           |
| ---------------- | -------------------------------------------------- |
| `NULL` (default) | No forcing, use normal skip logic                  |
| `TRUE`           | Force reprocess ALL documents                      |
| `integer vector` | Force reprocess only these specific `document_id`s |

Example usage:

```r
# Force re-extract everything
process_documents("pdfs/", force_reprocess_extraction = TRUE)

# Force re-extract only documents 5 and 12
process_documents("pdfs/", force_reprocess_extraction = c(5L, 12L))
```

### Cascade behavior

| Parameter                    | Forces     | Cascades To          |
| ---------------------------- | ---------- | -------------------- |
| `force_reprocess_ocr`        | OCR        | Metadata, Extraction |
| `force_reprocess_metadata`   | Metadata   | Extraction           |
| `force_reprocess_extraction` | Extraction | (nothing)            |

When forcing specific document_ids, cascade only affects those documents.

**Note**: Refinement has no `force_reprocess` parameter. It's controlled by `run_refinement`:

| Value             | Behavior                                             |
| ----------------- | ---------------------------------------------------- |
| `FALSE` (default) | Don't run refinement                                 |
| `TRUE`            | Run refinement on ALL documents (that have records)  |
| `integer vector`  | Run refinement only on these specific `document_id`s |

## Implementation Logic

```
# Pseudocode for process_single_document

# Helper function: check if this document should be forced
is_forced <- function(force_param, document_id) {
  if (is.null(force_param)) return FALSE
  if (isTRUE(force_param)) return TRUE
  if (is.numeric(force_param)) return document_id %in% force_param
  return FALSE
}

# Helper function: check if step should run (for OCR and Metadata)
should_run_step <- function(status, data_exists, force_param, document_id, upstream_ran) {
  if (is_forced(force_param, document_id) OR upstream_ran) {
    return TRUE
  }
  if (status != "completed") {
    return TRUE
  }
  if (status == "completed" AND !data_exists) {
    set status = "Error: Status was completed but no data found in DB"
    return TRUE
  }
  return FALSE  # status == "completed" AND data exists → skip
}

# Helper function: check if step should run (status-only, for Extraction)
should_run_step_status_only <- function(status, force_param, document_id, upstream_ran) {
  if (is_forced(force_param, document_id) OR upstream_ran) {
    return TRUE
  }
  if (status != "completed") {
    return TRUE
  }
  return FALSE  # status == "completed" → skip
}

# Track what actually ran (for cascade)
ocr_ran <- FALSE
metadata_ran <- FALSE
# Note: extraction_ran not needed - extraction doesn't cascade to anything

# Step 1: OCR
ocr_data_exists <- (document_content IS NOT NULL AND document_content != '')
if (should_run_step(ocr_status, ocr_data_exists, force_reprocess_ocr, document_id, FALSE)) {
  run OCR
  ocr_ran <- TRUE
}

# Step 2: Metadata
metadata_data_exists <- (title OR first_author_lastname OR publication_year is populated)
if (should_run_step(metadata_status, metadata_data_exists, force_reprocess_metadata, document_id, ocr_ran)) {
  run Metadata
  metadata_ran <- TRUE
}

# Step 3: Extraction (status-only check - zero records is valid)
if (run_extraction AND should_run_step_status_only(extraction_status, force_reprocess_extraction, document_id, metadata_ran)) {
  run Extraction
}

# Step 4: Refinement (opt-in, no skip logic)
# run_refinement can be: FALSE, TRUE, or integer vector of document_ids
# Only runs if: run_refinement includes this document AND records exist
records_exist <- (record count > 0 for this document)
should_refine <- (isTRUE(run_refinement) OR (is.numeric(run_refinement) AND document_id %in% run_refinement))
if (should_refine AND records_exist) {
  run Refinement
}
```

## Cascade Mechanism: Status Nullification (Not Deletion)

**Decision**: Never delete data. Only humans should delete records.

When forcing a step, set downstream status columns to NULL in the `documents` table. This marks them as "needs to re-run" without destroying data.

| Force Parameter              | Sets to NULL                           |
| ---------------------------- | -------------------------------------- |
| `force_reprocess_ocr`        | `metadata_status`, `extraction_status` |
| `force_reprocess_metadata`   | `extraction_status`                    |
| `force_reprocess_extraction` | (nothing)                              |

The skip logic then checks status: if NULL, the step must run.

## Extraction vs Refinement: Separation of Concerns

| Step           | Mode              | Behavior                                            |
| -------------- | ----------------- | --------------------------------------------------- |
| **Extraction** | `mode = "insert"` | Adds new rows ONLY. Never updates existing records. |
| **Refinement** | `mode = "update"` | Updates existing rows ONLY. Never adds new records. |

This is a deliberate design choice:

- Extraction finds new records in the document
- Refinement improves/enriches records that already exist

## Deduplication Behavior (Extraction Only)

When extraction runs, deduplication prevents duplicate inserts:

1. Uses `x-unique-fields` from schema to define record uniqueness
2. Compares each new record against ALL existing records in DB
3. Field-by-field similarity comparison (embedding or Jaccard)
4. If ALL key fields match above threshold → record is duplicate, **not inserted**
5. Only genuinely new/different records get added

**Implications**:

- Re-running extraction is safe - won't create duplicates
- Existing records are never modified by extraction
- If LLM extracts same record again, it's silently skipped
- If LLM extracts a slightly different version, it may be added as new (depends on similarity threshold)

## Prompt Hash (No Auto-Invalidation)

**Decision**: Store `prompt_hash` per-record (already implemented), but no automatic staleness detection.

- User is responsible for using `force_reprocess_extraction` if they change their prompt
- Human oversight preferred over automatic re-extraction

## Current State vs. Proposed (Code Audit)

### OCR (`R/ocr.R`)

| Aspect          | Current                                      | Proposed                                                          |
| --------------- | -------------------------------------------- | ----------------------------------------------------------------- |
| Skip check      | Data-first: checks `document_content` exists | Status-first: check `ocr_status == "completed"`, then verify data |
| Status column   | `ocr_status` updated after run               | Same                                                              |
| force_reprocess | Boolean only                                 | `NULL` / `TRUE` / integer vector                                  |

### Metadata (`R/metadata.R`)

| Aspect          | Current                                                                 | Proposed                                                               |
| --------------- | ----------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Skip check      | Data-first: checks `title`, `first_author_lastname`, `publication_year` | Status-first: check `metadata_status == "completed"`, then verify data |
| Data fields     | `title`, `first_author_lastname`, `publication_year`                    | Same (doc said `authors` but code uses `first_author_lastname`)        |
| Status column   | Updated by workflow, not function                                       | Same                                                                   |
| force_reprocess | Boolean only                                                            | `NULL` / `TRUE` / integer vector                                       |

### Extraction (`R/extraction.R`)

| Aspect                | Current                                                 | Proposed                                                                                 |
| --------------------- | ------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Skip check            | **NONE** - always runs                                  | Status-only: check `extraction_status == "completed"` (zero records is valid result)     |
| force_reprocess param | Exists but **never used** (hardcoded FALSE in workflow) | `NULL` / `TRUE` / integer vector                                                         |
| Status column         | Updated by workflow                                     | Same                                                                                     |

### Refinement (`R/refinement.R`)

| Aspect                | Current                                   | Proposed                                                               |
| --------------------- | ----------------------------------------- | ---------------------------------------------------------------------- |
| Skip check            | Only checks `nrow(existing_records) == 0` | Same - refinement is opt-in via `run_refinement`, no skip logic needed |
| force_reprocess param | Does not exist                            | Not needed - controlled by `run_refinement` flag                       |
| Status column         | Updated by workflow                       | Same                                                                   |

### Cascade Logic (`R/workflow.R`)

| Aspect               | Current  | Proposed                                             |
| -------------------- | -------- | ---------------------------------------------------- |
| `*_ran` tracking     | **None** | Add `ocr_ran`, `metadata_ran` flags                  |
| Status nullification | **None** | Set downstream status to NULL when upstream runs     |
| Cascade on force     | **None** | Nullify downstream statuses for affected documents   |

## Summary of Changes Needed

1. **Add parameters to `process_documents()`**:
   - `force_reprocess_extraction` (new)
   - Change all `force_reprocess_*` from boolean to `NULL`/`TRUE`/integer vector
   - (No `force_reprocess_refinement` - controlled by existing `run_refinement` flag)

2. **Implement `is_forced()` helper**: Check if document should be forced based on param type

3. **Implement `should_run_step()` helper**: Status-first check with data verification and desync handling

4. **Fix extraction skip logic**:
   - `extract_records()` needs to check `extraction_status` only (not record count)
   - Remove hardcoded `force_reprocess = FALSE` in workflow

5. **Update `run_refinement` parameter**:
   - Change from boolean to `FALSE`/`TRUE`/integer vector
   - Check if document_id is included before running

6. **Add cascade tracking in workflow**:
   - Track `ocr_ran`, `metadata_ran` flags (extraction doesn't cascade to anything)
   - When step runs, nullify downstream status columns

7. **Update OCR/Metadata to status-first**:
   - Check status column before checking data
   - Add desync error handling
