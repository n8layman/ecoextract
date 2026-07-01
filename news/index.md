# Changelog

## ecoextract 0.1.12

### Bug fixes

- [`save_document()`](https://n8layman.github.io/ecoextract/reference/save_document.md)
  now assigns `id` after inserting a user-added row, fixing infinite
  duplication on repeated verify clicks in databases created with the
  old schema where `id` was a plain `INTEGER` rather than
  `INTEGER PRIMARY KEY`. After each insert,
  `UPDATE records SET id = last_insert_rowid() WHERE rowid = last_insert_rowid()`
  is executed; this is a no-op on new-schema databases where `id` is
  already set by autoincrement.

## ecoextract 0.1.11

### Bug fixes

- [`save_document()`](https://n8layman.github.io/ecoextract/reference/save_document.md)
  no longer silently drops user-added rows when the document has zero
  LLM-extracted records. Previously the diff/insert block was guarded by
  `nrow(original_df) > 0`, which skipped the insert path when
  `original_df` was an empty tibble. The
  [`nrow()`](https://rdrr.io/r/base/nrow.html) guard is removed;
  [`diff_records()`](https://n8layman.github.io/ecoextract/reference/diff_records.md)
  already handles a 0-row `original_df` correctly. Passing
  `original_df = NULL` still skips record changes as documented.

## ecoextract 0.1.10

### Bug fixes

- Fixed `document_id <- NA` clobber in
  [`ocr_document()`](https://n8layman.github.io/ecoextract/reference/ocr_document.md)
  that caused reprocessing via `document_id` to create a duplicate
  documents row when the file hash had changed (e.g. after opening and
  re-saving the PDF).

- `process_documents(document_id = X, force_reprocess_ocr = TRUE)` now
  returns a clear `"file not found"` status and leaves the database
  untouched when the stored file path no longer exists, instead of
  nullifying `ocr_status` and failing mid-pipeline. A subsequent run
  without `force_reprocess_ocr` will use the stored OCR content.

### Improvements

- PDF file paths are now stored relative to the project root (found by
  walking up from the PDF file’s directory until a `.git`, `.Rproj`,
  `DESCRIPTION`, or `.here` marker is found). This makes paths portable
  across machines and when the project folder is moved. **If no project
  root marker is found the absolute path is stored as a fallback** —
  this is machine-specific and will break if the database is shared or
  the project folder is moved.

- When a document is identified by hash match but the file has moved to
  a new path, `file_path` in the database is immediately updated to
  reflect the current location.

## ecoextract 0.1.9

### Bug fixes

- `process_documents(document_id = ...)` now correctly reprocesses the
  specified document in-place instead of creating a duplicate row when
  the file’s hash has changed since initial processing (e.g. after
  opening and re-saving the PDF). The original `document_id` is passed
  through to
  [`process_single_document()`](https://n8layman.github.io/ecoextract/reference/process_single_document.md)
  and used directly, bypassing the hash lookup.

## ecoextract 0.1.8

### Improvements

- Extraction now uses a two-turn LLM conversation: turn 1 produces
  structured reasoning (capturing document analysis, organism
  identifiability decisions, and extraction choices), turn 2 uses that
  reasoning as context to extract structured records. This ensures
  reasoning causally precedes extraction rather than being a sibling
  field in the same structured output call, fixing divergence between
  stated reasoning and extracted records.

- `reasoning` removed from the extraction JSON schema — it is now always
  captured via the two-turn structure and stored in the database
  regardless of schema configuration.

- Content refusals on turn 1 are now correctly detected and logged as
  refusals rather than retried as stochastic empty-reasoning failures.

## ecoextract 0.1.7

- Initial release.
