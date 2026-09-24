# Complete Document Processing Workflow

Process PDFs through the complete pipeline: OCR → Metadata → Extract →
Refine

## Usage

``` r
process_documents(
  pdf_path = NULL,
  document_id = NULL,
  db_conn = "ecoextract_records.db",
  schema_file = NULL,
  extraction_prompt_file = NULL,
  refinement_prompt_file = NULL,
  metadata_schema_file = NULL,
  metadata_prompt_file = NULL,
  model = "anthropic/claude-sonnet-5",
  reasoning_effort = NULL,
  ocr_provider = "mistral",
  ocr_timeout = 300,
  force_reprocess_ocr = NULL,
  force_reprocess_metadata = NULL,
  force_reprocess_extraction = NULL,
  run_metadata = TRUE,
  run_extraction = TRUE,
  run_refinement = NULL,
  min_similarity = 0.9,
  embedding_provider = "openai",
  similarity_method = "llm",
  reps = 1,
  recursive = FALSE,
  workers = NULL,
  log = FALSE,
  ...
)
```

## Arguments

- pdf_path:

  Path to a single PDF file, a character vector of PDF paths, or a
  directory of PDFs. Mutually exclusive with `document_id`. If neither
  `pdf_path` nor `document_id` is given, all documents in `db_conn` are
  processed.

- document_id:

  Integer vector of document IDs from the database to reprocess. For
  each ID, the stored file path is looked up; if the file exists on disk
  it is used, otherwise the stored OCR content is used directly.
  Mutually exclusive with `pdf_path`. If neither `pdf_path` nor
  `document_id` is given, all documents in `db_conn` are processed.

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

- metadata_schema_file:

  Optional custom metadata schema. Defaults to
  `ecoextract/metadata_schema.json` if present, otherwise the package's
  bibliographic schema.

- metadata_prompt_file:

  Optional custom metadata prompt. Defaults to
  `ecoextract/metadata_prompt.md` if present, otherwise the package
  prompt.

- model:

  LLM model(s) to use for metadata extraction, record extraction, and
  refinement. Can be a single model name (character string) or a vector
  of models for tiered fallback. When a vector is provided, models are
  tried sequentially until one succeeds. Default:
  "anthropic/claude-sonnet-5". Examples: "openai/gpt-4.1",
  "google_gemini/gemini-2.5-flash", c("anthropic/claude-sonnet-5",
  "google_gemini/gemini-2.5-flash", "mistral/mistral-large-latest")

- reasoning_effort:

  How much the model thinks before answering, for every LLM step
  (metadata, extraction, refinement, deduplication). NULL (default)
  turns thinking off for Claude and Gemini, which is faster and cheaper;
  other providers use their model default. Set an effort level such as
  "low", "medium", or "high" to turn thinking on. Thinking tokens are
  billed as output and are counted in the `<step>_output_tokens`
  columns.

- ocr_provider:

  OCR provider(s) to use (default: "mistral"). Accepts a character
  vector for fallback, e.g. `c("tensorlake", "mistral")` tries
  tensorlake first and falls back to mistral on failure. Options:
  "tensorlake", "mistral", "claude"

- ocr_timeout:

  Maximum seconds to wait for OCR completion (default: 300)

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

- run_metadata:

  If TRUE, run metadata step. Default TRUE. Set FALSE for corpora with
  no useful document metadata (e.g. when record IDs come from
  `document_id` or `file_name`) to skip one LLM call per document.

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

- reps:

  Number of extraction passes (default: 1). Multiple passes increase
  recall by deduplicating each pass against accumulated results.

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

  Additional arguments (deprecated: use explicit parameters instead)

## Value

Tibble with processing results

## Examples

``` r
if (FALSE) { # \dontrun{
# Basic usage - process new PDFs
process_documents("pdfs/")
process_documents("paper.pdf", "my_interactions.db")

# Reprocess specific documents by ID (works even if files have moved/been deleted)
process_documents(document_id = c(1L, 5L, 12L), db_conn = "my_interactions.db")

# Reprocess all documents currently in the database
ids <- DBI::dbGetQuery(con, "SELECT document_id FROM documents")$document_id
process_documents(document_id = ids, db_conn = con)

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

# Custom metadata schema and prompt for a non-literature corpus
process_documents("pdfs/",
                  metadata_schema_file = "config/metadata_schema.json",
                  metadata_prompt_file = "config/metadata_prompt.md")

# Skip the metadata step (e.g. record IDs built from document_id)
process_documents("pdfs/", run_metadata = FALSE)

# Search for PDFs in all subdirectories
process_documents("research_papers/", recursive = TRUE)

# Process in parallel with 4 workers (requires crew package)
process_documents("pdfs/", workers = 4)

# Parallel with logging for troubleshooting
process_documents("pdfs/", workers = 4, log = TRUE)

# Use different OCR provider
process_documents("pdfs/", ocr_provider = "mistral")

# Increase OCR timeout to 5 minutes for large documents
process_documents("pdfs/", ocr_timeout = 300)
} # }
```
