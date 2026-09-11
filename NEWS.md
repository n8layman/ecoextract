# ecoextract 0.1.21

## New features

* Projects can supply their own metadata schema and prompt, via
  `ecoextract/metadata_schema.json` and `ecoextract/metadata_prompt.md` or the
  new `metadata_schema_file` and `metadata_prompt_file` arguments to
  `process_documents()`. Fields not already in the `documents` table are added
  as columns (#138).
* New `run_metadata` argument to `process_documents()` skips the metadata step
  (#138).
* Record IDs are built from the fields named in the metadata schema's
  `x-record-id-fields` (metadata fields, `document_id`, or `file_name`) instead
  of hardcoded author and year. The default schema keeps
  `first_author_lastname` and `publication_year`, so default IDs are unchanged
  (`Smith_2020_1_r1`) (#138).

## Breaking changes

* The default model is now `anthropic/claude-sonnet-5` (was
  `anthropic/claude-sonnet-4-5`) for all steps (#142).
* A document's metadata now counts as present if any metadata schema field is
  populated. Previously title, first author, and year were all required, so
  documents missing one re-ran metadata on every pass.
* Missing record ID values become `Unknown` (previously a missing year became
  the current year).

## Bug fixes

* Schemas sent to Anthropic and OpenAI now have `"additionalProperties": false`
  on every object instead of having it stripped, which Claude Sonnet 4.6
  rejected with HTTP 400. Gemini schemas still have it removed (#140).
* The default metadata schema lists every field in `required` (with nullable
  types), so it stays within the structured-output limits of older models such
  as Claude Sonnet 4.6 and Haiku 4.5 (#142).
* When every model fails, the error message links to the README's new
  Troubleshooting section (#142).

## Documentation

* README and configuration guide cover custom metadata schemas and
  troubleshooting unexplained schema errors, including measured model limits
  (#142).

# ecoextract 0.1.20

## Minor improvements

* Parallel worker completion messages now include `document_id`.

# ecoextract 0.1.19

## New features

* `process_documents()` now accepts `db_conn` alone — omitting both `pdf_path`
  and `document_id` processes all documents already in the database. Useful for
  re-running extraction on a database that was split from a larger one.

# ecoextract 0.1.18

## Bug fixes

* `process_documents()` with `workers > 1` now passes a unique seed to each
  parallel worker via `crew`'s `seed` argument. Previously, workers spawned
  simultaneously could inherit identical RNG state and generate colliding UUIDs,
  causing UNIQUE constraint failures on `records.id`.

# ecoextract 0.1.17

## Bug fixes

* `process_documents()` with `force_reprocess_extraction` now deletes existing
  unedited records for the document before re-extracting, instead of relying on
  dedup to filter them out. This prevents record accumulation across multiple
  force runs and eliminates the risk of UNIQUE constraint failures on
  `records.id`. Human-edited records (those with entries in `record_edits`) are
  preserved.

# ecoextract 0.1.16

## Bug fixes

* `save_document()` now correctly includes `id` (UUID) when inserting into
  `record_edits`. Since 0.1.13 the column is `TEXT PRIMARY KEY` (NOT NULL), so
  omitting it caused every cell edit followed by Verify to fail with a NOT NULL
  constraint error and roll back the entire save (#133).

* Extraction write failures are no longer silently swallowed. When
  `save_records_to_db()` throws, the error message is now written into
  `extraction_status` (e.g. `"Extraction failed: ..."`) rather than leaving
  the document marked `"completed"` with 0 records extracted (#134).

# ecoextract 0.1.15

## Bug fixes

* `get_document_content()` no longer throws `"missing value where TRUE/FALSE
  needed"` when `document_content` is `NULL` in the database (returned as `NA`
  in R). The `is.null()` check did not catch `NA`, causing `NA == ""` to
  evaluate to `NA` and `if(NA)` to error. Fixed by extracting the value first
  and checking with `is.na()` / `nzchar()`.

# ecoextract 0.1.14

## Bug fixes

* `migrate_ecoextract_database()` now correctly upgrades databases whose
  `records` table was created by `dbWriteTable` rather than
  `init_ecoextract_database()`. The previous approach patched the DDL string
  from `sqlite_master`, which silently failed when column names were
  backtick-quoted or `AUTOINCREMENT` was absent. The migration now builds the
  new DDL from `PRAGMA table_info` and uses `ALTER TABLE ... RENAME TO` /
  `CREATE TABLE` / `dbAppendTable` / `DROP TABLE` instead of DROP + CREATE +
  `dbWriteTable`, so the schema change is guaranteed regardless of how the
  original table was created.

* Records with `NULL` id (possible when the original table was created without
  `AUTOINCREMENT`) now receive a fresh UUID during migration instead of
  remaining NULL.

* Schema migration warning is now issued from `get_records()` (as a message,
  printed immediately) and `save_document()` (as a hard error) rather than
  from `init_ecoextract_database()`, which is only called when creating new
  databases. Old-schema databases opened for reading or writing are now always
  surfaced correctly.

# ecoextract 0.1.13

## Improvements

* `records.id` is now `TEXT PRIMARY KEY` (UUID v4) instead of
  `INTEGER PRIMARY KEY AUTOINCREMENT`. UUIDs are generated in R using base
  functions only (no new dependency). This makes records collision-free when
  merging databases from independent researchers.

* Added `migrate_ecoextract_database()` to upgrade existing databases created
  before 0.1.13. The function recreates `records` and `record_edits` with TEXT
  ids, backfills UUIDs from a per-session integer-to-UUID map, and runs the
  entire operation in a single transaction. Safe to re-run.

* `init_ecoextract_database()` now warns when it detects the old integer-id
  schema, prompting the user to run `migrate_ecoextract_database()`.

* All record insert paths (bulk extraction via `save_records_to_db()` and
  single-row user additions via `save_document()`) now generate UUIDs for rows
  that do not already have an id.

# ecoextract 0.1.12

## Bug fixes

* `save_document()` now assigns `id` after inserting a user-added row, fixing
  infinite duplication on repeated verify clicks in databases created with the
  old schema where `id` was a plain `INTEGER` rather than `INTEGER PRIMARY KEY`.
  After each insert, `UPDATE records SET id = last_insert_rowid() WHERE rowid =
  last_insert_rowid()` is executed; this is a no-op on new-schema databases
  where `id` is already set by autoincrement.

# ecoextract 0.1.11

## Bug fixes

* `save_document()` no longer silently drops user-added rows when the document
  has zero LLM-extracted records. Previously the diff/insert block was guarded
  by `nrow(original_df) > 0`, which skipped the insert path when `original_df`
  was an empty tibble. The `nrow()` guard is removed; `diff_records()` already
  handles a 0-row `original_df` correctly. Passing `original_df = NULL` still
  skips record changes as documented.

# ecoextract 0.1.10

## Bug fixes

* Fixed `document_id <- NA` clobber in `ocr_document()` that caused
  reprocessing via `document_id` to create a duplicate documents row when the
  file hash had changed (e.g. after opening and re-saving the PDF).

* `process_documents(document_id = X, force_reprocess_ocr = TRUE)` now returns
  a clear `"file not found"` status and leaves the database untouched when the
  stored file path no longer exists, instead of nullifying `ocr_status` and
  failing mid-pipeline. A subsequent run without `force_reprocess_ocr` will use
  the stored OCR content.

## Improvements

* PDF file paths are now stored relative to the project root (found by walking
  up from the PDF file's directory until a `.git`, `.Rproj`, `DESCRIPTION`, or
  `.here` marker is found). This makes paths portable across machines and when
  the project folder is moved. **If no project root marker is found the absolute
  path is stored as a fallback** — this is machine-specific and will break if
  the database is shared or the project folder is moved.

* When a document is identified by hash match but the file has moved to a new
  path, `file_path` in the database is immediately updated to reflect the
  current location.

# ecoextract 0.1.9

## Bug fixes

* `process_documents(document_id = ...)` now correctly reprocesses the
  specified document in-place instead of creating a duplicate row when the
  file's hash has changed since initial processing (e.g. after opening and
  re-saving the PDF). The original `document_id` is passed through to
  `process_single_document()` and used directly, bypassing the hash lookup.

# ecoextract 0.1.8

## Improvements

* Extraction now uses a two-turn LLM conversation: turn 1 produces structured
  reasoning (capturing document analysis, organism identifiability decisions, and
  extraction choices), turn 2 uses that reasoning as context to extract structured
  records. This ensures reasoning causally precedes extraction rather than being
  a sibling field in the same structured output call, fixing divergence between
  stated reasoning and extracted records.

* `reasoning` removed from the extraction JSON schema — it is now always
  captured via the two-turn structure and stored in the database regardless of
  schema configuration.

* Content refusals on turn 1 are now correctly detected and logged as refusals
  rather than retried as stochastic empty-reasoning failures.

# ecoextract 0.1.7

* Initial release.
