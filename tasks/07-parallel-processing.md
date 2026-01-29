# Parallel Processing with crew

## Overview

Add parallel document processing to `process_documents()` using the `crew` package. Each worker processes documents independently, writing directly to the main SQLite database with WAL mode enabled.

## Design Decisions

### Why crew?

| Consideration | crew advantage |
|---------------|----------------|
| API rate limiting | Built-in `seconds_interval` between tasks |
| Worker overhead | Persistent workers (no R restart per task) |
| Crash recovery | Tasks complete independently |
| Cloud scaling | crew.aws.batch, crew.cluster available |

### Why WAL mode for SQLite?

- Multiple concurrent readers allowed
- Single writer at a time (others queue briefly)
- API calls take 30-180s; DB writes take milliseconds
- Write serialization is negligible compared to API latency

### Why dedup works per-worker?

Deduplication only matters within the context of a single document:
- Checks new records against existing records *for the same document*
- No cross-document deduplication needed
- Each worker is fully independent

## Implementation Plan

### Phase 1: Dependencies and Configuration

#### 1.1 Add crew to DESCRIPTION

```
Suggests:
    crew,
    ...
```

#### 1.2 Enable WAL mode in configure_sqlite_connection()

File: `R/database.R`

```r
configure_sqlite_connection <- function(conn) {
 DBI::dbExecute(conn, "PRAGMA busy_timeout = 30000")
 DBI::dbExecute(conn, "PRAGMA journal_mode = WAL")
 # ... existing pragmas
}
```

Note: WAL mode persists on the database file, only needs to be set once.

### Phase 2: Update process_documents()

#### 2.1 Add workers parameter

File: `R/workflow.R`

```r
#' @param workers Number of parallel workers. NULL (default) or 1 for sequential
#'   processing. Requires the crew package for parallel execution.
process_documents <- function(pdf_path,
                             db_conn = "ecoextract_records.db",
                             ...,
                             workers = NULL) {
```

#### 2.2 Validate workers parameter

```r
# Validate workers parameter
if (!is.null(workers)) {
 if (!is.numeric(workers) || workers < 1) {
   stop("workers must be NULL or a positive integer")
 }
 if (workers > 1 && !requireNamespace("crew", quietly = TRUE)) {
   stop("Package 'crew' required for parallel processing. Install with: install.packages('crew')")
 }
}
```

#### 2.3 Convert db_conn to path for workers

Workers need a path string, not a connection object:

```r
# For parallel processing, we need a DB path (not connection)
if (!is.null(workers) && workers > 1) {
 if (inherits(db_conn, "DBIConnection")) {
   stop("Parallel processing requires db_conn to be a file path, not a connection object")
 }
 db_path <- db_conn
} else {
 db_path <- NULL
}
```

#### 2.4 Parallel execution branch

```r
if (!is.null(workers) && workers > 1) {
 results_list <- process_documents_parallel(
   pdf_files = pdf_files,
   db_path = db_path,
   workers = workers,
   schema_file = schema_src$path,
   extraction_prompt_file = extraction_prompt_file,
   refinement_prompt_file = refinement_prompt_file,
   force_reprocess_ocr = force_reprocess_ocr,
   force_reprocess_metadata = force_reprocess_metadata,
   force_reprocess_extraction = force_reprocess_extraction,
   run_extraction = run_extraction,
   run_refinement = run_refinement,
   min_similarity = min_similarity,
   embedding_provider = embedding_provider,
   similarity_method = similarity_method
 )
} else {
 # Existing sequential loop
 for (pdf_file in pdf_files) {
   ...
 }
}
```

### Phase 3: Create parallel execution function

#### 3.1 New function: process_documents_parallel()

File: `R/workflow.R` (or new file `R/parallel.R`)

```r
#' Process documents in parallel using crew
#'
#' @keywords internal
process_documents_parallel <- function(pdf_files,
                                       db_path,
                                       workers,
                                       schema_file,
                                       extraction_prompt_file,
                                       refinement_prompt_file,
                                       force_reprocess_ocr,
                                       force_reprocess_metadata,
                                       force_reprocess_extraction,
                                       run_extraction,
                                       run_refinement,
                                       min_similarity,
                                       embedding_provider,
                                       similarity_method) {

 # Initialize crew controller
 controller <- crew::crew_controller_local(
   workers = workers,
   seconds_idle = 60  # Workers terminate after 60s idle
 )
 controller$start()
 on.exit(controller$terminate(), add = TRUE)

 # Push tasks for each PDF
 for (i in seq_along(pdf_files)) {
   controller$push(
     command = ecoextract::process_single_document(
       pdf_file = pdf_file,
       db_conn = db_path,
       schema_file = schema_file,
       extraction_prompt_file = extraction_prompt_file,
       refinement_prompt_file = refinement_prompt_file,
       force_reprocess_ocr = force_reprocess_ocr,
       force_reprocess_metadata = force_reprocess_metadata,
       force_reprocess_extraction = force_reprocess_extraction,
       run_extraction = run_extraction,
       run_refinement = run_refinement,
       min_similarity = min_similarity,
       embedding_provider = embedding_provider,
       similarity_method = similarity_method
     ),
     data = list(
       pdf_file = pdf_files[i],
       db_path = db_path,
       schema_file = schema_file,
       extraction_prompt_file = extraction_prompt_file,
       refinement_prompt_file = refinement_prompt_file,
       force_reprocess_ocr = force_reprocess_ocr,
       force_reprocess_metadata = force_reprocess_metadata,
       force_reprocess_extraction = force_reprocess_extraction,
       run_extraction = run_extraction,
       run_refinement = run_refinement,
       min_similarity = min_similarity,
       embedding_provider = embedding_provider,
       similarity_method = similarity_method
     ),
     name = basename(pdf_files[i])
   )
 }

 # Collect results with progress reporting
 results_list <- list()
 completed <- 0
 errors <- 0
 total <- length(pdf_files)

 while (completed < total) {
   # Pop completed tasks
   result <- controller$pop()

   if (!is.null(result)) {
     completed <- completed + 1

     if (!is.null(result$error)) {
       errors <- errors + 1
       # Create error result
       results_list[[completed]] <- list(
         filename = result$name,
         document_id = NA,
         ocr_status = paste("Error:", result$error),
         metadata_status = "skipped",
         extraction_status = "skipped",
         refinement_status = "skipped",
         records_extracted = 0
       )
     } else {
       results_list[[completed]] <- result$result
     }

     # Progress update
     cat(sprintf("\r[%d/%d] Completed: %d | Errors: %d",
                 completed, total, completed - errors, errors))
   }

   Sys.sleep(0.1)  # Brief pause to avoid busy-waiting
 }

 cat("\n")  # Newline after progress
 results_list
}
```

### Phase 4: Export process_single_document

Currently `process_single_document` is internal. For crew workers to call it, we need to either:

**Option A: Export it**

```r
#' @export
process_single_document <- function(...) {
```

Update NAMESPACE via roxygen2.

**Option B: Keep internal, use crew's data passing**

Pass the function definition in the data list. More complex, prefer Option A.

### Phase 5: Suppress verbose logging in parallel mode

#### 5.1 Add quiet parameter to process_single_document

```r
process_single_document <- function(pdf_file,
                                    db_conn,
                                    ...,
                                    quiet = FALSE) {
 if (!quiet) {
   message(strrep("=", 70))
   message(glue::glue("Processing: {basename(pdf_file)}"))
 }
 ...
}
```

#### 5.2 Pass quiet = TRUE in parallel mode

```r
controller$push(
 command = ecoextract::process_single_document(
   ...,
   quiet = TRUE
 ),
 ...
)
```

### Phase 6: Update documentation

#### 6.1 Update roxygen for process_documents

Add `@param workers` documentation.

#### 6.2 Add examples

```r
#' @examples
#' \dontrun{
#' # Process in parallel with 4 workers
#' process_documents("pdfs/", workers = 4)
#' }
```

#### 6.3 Update README.md

Add section on parallel processing:

```markdown
## Parallel Processing

Process multiple documents in parallel using the `crew` package:

\`\`\`r
# Install crew (optional dependency)
install.packages("crew")

# Process with 4 parallel workers
results <- process_documents(
 pdf_path = "papers/",
 db_conn = "records.db",
 workers = 4
)
\`\`\`

Notes:
- Requires `db_conn` to be a file path (not a connection object)
- Each worker opens its own database connection
- Progress is shown as documents complete
- Crash-resilient: completed documents are saved immediately
\`\`\`
```

## Testing Plan

### Unit Tests

1. **Test workers parameter validation**
   - `workers = NULL` → sequential
   - `workers = 1` → sequential
   - `workers = 4` → parallel (if crew installed)
   - `workers = -1` → error
   - `workers = "four"` → error

2. **Test crew not installed**
   - Mock `requireNamespace` returning FALSE
   - Expect informative error message

3. **Test db_conn validation in parallel mode**
   - Connection object with workers > 1 → error
   - Path string with workers > 1 → OK

### Integration Tests

1. **Test parallel processing produces same results as sequential**
   - Process same PDFs both ways
   - Compare final database state

2. **Test crash recovery**
   - Start parallel processing
   - Simulate worker failure (harder to test)
   - Verify completed documents persisted

3. **Test WAL mode enabled**
   - Check `PRAGMA journal_mode` returns "wal"

## File Changes Summary

| File | Changes |
|------|---------|
| `DESCRIPTION` | Add crew to Suggests |
| `R/database.R` | Enable WAL mode in configure_sqlite_connection() |
| `R/workflow.R` | Add workers param, parallel execution branch, process_documents_parallel() |
| `NAMESPACE` | Export process_single_document |
| `man/process_documents.Rd` | Update documentation |
| `README.md` | Add parallel processing section |
| `tests/testthat/test-parallel.R` | New test file |

## Rollout

1. Implement Phase 1-2 (dependencies, parameter)
2. Implement Phase 3-4 (parallel function, export)
3. Implement Phase 5 (quiet mode)
4. Add tests
5. Update documentation
6. Test manually with real PDFs
7. Merge

## Future Enhancements

- Rate limiting via `crew_controller_local(seconds_interval = X)`
- Cloud workers via `crew.aws.batch` or `crew.cluster`
- Progress bar instead of text updates (progressr integration)
- Configurable worker idle timeout
