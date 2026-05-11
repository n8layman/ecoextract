# Duplicate a template database for benchmark trials

Creates N copies of a template database, preserving pipeline state up to
a specified stage. This avoids re-running expensive deterministic steps
(like OCR) across benchmark trials.

## Usage

``` r
duplicate_for_trials(
  template_db,
  n,
  through = c("ocr", "metadata", "extraction"),
  pattern = NULL,
  dir = NULL
)
```

## Arguments

- template_db:

  Path to the template SQLite database

- n:

  Number of trial copies to create

- through:

  Pipeline stage to preserve. One of:

  "ocr"

  :   Keep OCR results. Trials re-run metadata, extraction, and
      refinement.

  "metadata"

  :   Keep OCR + metadata. Trials re-run extraction and refinement.

  "extraction"

  :   Keep OCR + metadata + extraction. Trials only re-run refinement.

- pattern:

  Naming pattern for trial databases. Use `{n}` for the trial number
  (glue syntax). Default: `"{basename}_trial_{n}.{ext}"` where basename
  and ext come from the template filename.

- dir:

  Output directory for trial databases (default: same directory as
  template)

## Value

Character vector of paths to the created trial databases

## Examples

``` r
if (FALSE) { # \dontrun{
# Create 10 trial copies preserving OCR
trial_dbs <- duplicate_for_trials("template.db", n = 10, through = "ocr")

# Custom naming pattern
trial_dbs <- duplicate_for_trials("template.db", n = 5, pattern = "benchmark_trial_{n}.sqlite")

# Run pipeline on each trial (OCR auto-skips)
results <- purrr::map(trial_dbs, \(db) {
  process_documents("pdfs/", db_conn = db)
})
} # }
```
