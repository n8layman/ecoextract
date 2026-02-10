# Complete Document Processing Workflow

Process PDFs through the complete pipeline: OCR → Metadata → Extract →
Refine

## Usage

``` r
process_documents(
  pdf_path,
  db_conn = "ecoextract_records.db",
  schema_file = NULL,
  extraction_prompt_file = NULL,
  refinement_prompt_file = NULL,
  force_reprocess_ocr = NULL,
  force_reprocess_metadata = NULL,
  force_reprocess_extraction = NULL,
  run_extraction = TRUE,
  run_refinement = NULL,
  min_similarity = 0.9,
  embedding_provider = "openai",
  similarity_method = "llm",
  recursive = FALSE,
  workers = NULL,
  log = FALSE,
  ...
)
```

## Arguments

- pdf_path:

  Path to a single PDF file or directory of PDFs

- db_conn:

  Database connection (any DBI backend) or path to SQLite database file.
  If a path is provided, creates SQLite database if it doesn't exist. If
  a connection is provided, tables must already exist (use
  [`init_ecoextract_database()`](https://n8layman.github.io/ecoextract/reference/init_ecoextract_database.md)
  first).

- schema_file:

  Optional custom schema file

- extraction_prompt_file:

  Optional custom extraction prompt

- refinement_prompt_file:

  Optional custom refinement prompt

- force_reprocess_ocr:

  Controls OCR reprocessing. NULL (default) uses normal skip logic, TRUE
  forces all documents, or an integer vector of document_ids to force
  specific documents.

- force_reprocess_metadata:

  Controls metadata reprocessing. NULL (default) uses normal skip logic,
  TRUE forces all documents, or an integer vector of document_ids to
  force specific documents.

- force_reprocess_extraction:

  Controls extraction reprocessing. NULL (default) uses normal skip
  logic, TRUE forces all documents, or an integer vector of document_ids
  to force specific documents.

- run_extraction:

  If TRUE, run extraction step to find new records. Default TRUE.

- run_refinement:

  Controls refinement step. NULL (default) skips refinement, TRUE runs
  on all documents with records, or an integer vector of document_ids to
  refine only specific documents.

- min_similarity:

  Minimum similarity for deduplication (default: 0.9)

- embedding_provider:

  Provider for embeddings when using embedding method (default:
  "openai")

- similarity_method:

  Method for deduplication similarity: "embedding", "jaccard", or "llm"
  (default: "llm")

- recursive:

  If TRUE and pdf_path is a directory, search for PDFs in all
  subdirectories. Default FALSE.

- workers:

  Number of parallel workers. NULL (default) or 1 for sequential
  processing. Values \> 1 require the crew package and db_conn must be a
  file path (not a connection object).

- log:

  If TRUE and using parallel processing (workers \> 1), write detailed
  output to an auto-generated log file (e.g.,
  ecoextract_20240129_143052.log). Default FALSE. Ignored for sequential
  processing. Useful for troubleshooting errors.

- ...:

  Additional arguments passed to underlying functions (e.g.,
  max_wait_seconds for OCR timeout)

## Value

Tibble with processing results

## Examples

``` r
if (FALSE) { # \dontrun{
# Basic usage - process new PDFs
process_documents("pdfs/")
process_documents("paper.pdf", "my_interactions.db")

# Remote database (Supabase, PostgreSQL, etc.)
library(RPostgres)
con <- dbConnect(Postgres(),
  dbname = "your_db",
  host = "db.xxx.supabase.co",
  user = "postgres",
  password = Sys.getenv("SUPABASE_PASSWORD")
)
# Initialize schema first
init_ecoextract_database(con)
# Then process documents
process_documents("pdfs/", db_conn = con)
dbDisconnect(con)

# Force re-run OCR for all documents (cascades to metadata and extraction)
process_documents("pdfs/", force_reprocess_ocr = TRUE)

# Force re-run OCR for specific documents only
process_documents("pdfs/", force_reprocess_ocr = c(5L, 12L))

# Force re-run metadata only (cascades to extraction)
process_documents("pdfs/", force_reprocess_metadata = TRUE)

# With custom schema and prompts
process_documents("pdfs/", "interactions.db",
                  schema_file = "ecoextract/schema.json",
                  extraction_prompt_file = "ecoextract/extraction_prompt.md")

# With refinement for all documents
process_documents("pdfs/", run_refinement = TRUE)

# Refinement for specific documents only
process_documents("pdfs/", run_refinement = c(5L, 12L))

# Skip extraction, refinement only on existing records
process_documents("pdfs/", run_extraction = FALSE, run_refinement = TRUE)

# Search for PDFs in all subdirectories
process_documents("research_papers/", recursive = TRUE)

# Process in parallel with 4 workers (requires crew package)
process_documents("pdfs/", workers = 4)

# Parallel with logging for troubleshooting
process_documents("pdfs/", workers = 4, log = TRUE)

# Increase OCR timeout to 5 minutes for large documents
process_documents("pdfs/", max_wait_seconds = 300)
} # }
```
