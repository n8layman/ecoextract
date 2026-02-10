# EcoExtract: Complete Workflow Guide

This guide walks you through the complete EcoExtract workflow – from
installation to validated, exported data. By the end, you’ll know how to
process PDFs, review extraction results, and calculate accuracy metrics.

## Setup

### The Three-Package Ecosystem

EcoExtract works as part of three packages:

| Package                                              | Purpose                                                                  |
|------------------------------------------------------|--------------------------------------------------------------------------|
| [ohseer](https://github.com/n8layman/ohseer)         | OCR processing – converts PDFs to markdown via Tensorlake                |
| [ecoextract](https://github.com/n8layman/ecoextract) | Data extraction pipeline – metadata, records, refinement, SQLite storage |
| [ecoreview](https://github.com/n8layman/ecoreview)   | Human review – Shiny app for editing, adding, deleting records           |

### Prerequisites

- R version 4.1.0 or higher
- RStudio (recommended)
- API keys for Tensorlake (OCR) and Anthropic Claude (extraction)

### Installation

Install all three packages from GitHub:

``` r
# Using pak (recommended)
pak::pak("n8layman/ohseer")      # OCR processing
pak::pak("n8layman/ecoextract")  # Data extraction
pak::pak("n8layman/ecoreview")   # Review app (optional)

# Or using devtools
devtools::install_github("n8layman/ohseer")
devtools::install_github("n8layman/ecoextract")
devtools::install_github("n8layman/ecoreview")
```

``` r
library(ecoextract)
```

**Optional dependencies:**

- `crew` – for parallel processing (`install.packages("crew")`)
- `ecoreview` – for human review of extracted records

### API Key Setup

EcoExtract requires API keys for OCR (Tensorlake) and data extraction
(Anthropic Claude).

**Get API keys from:**

- Tensorlake (for OCR): <https://www.tensorlake.ai/>
- Anthropic Claude (for extraction): <https://console.anthropic.com/>

**Before creating your `.env` file, verify it’s in `.gitignore`:**

``` bash
# Check that .env is in .gitignore
grep "^\.env$" .gitignore

# If not found, add it NOW before creating the file:
echo ".env" >> .gitignore
```

**Create a `.env` file in your project root:**

``` bash
ANTHROPIC_API_KEY=sk-ant-api03-your-key-here
TENSORLAKE_API_KEY=your-tensorlake-key-here
```

The `.env` file is automatically loaded when R starts in the project
directory. You can also load it manually:

``` r
readRenviron(".env")

# Or set keys directly in R
Sys.setenv(ANTHROPIC_API_KEY = "your_key_here")
Sys.setenv(TENSORLAKE_API_KEY = "your_key_here")

# Verify keys are loaded
Sys.getenv("ANTHROPIC_API_KEY")
Sys.getenv("TENSORLAKE_API_KEY")
```

**Verify before committing:**

``` bash
# This should show no output if .env is properly ignored:
git status | grep ".env"
```

### Verify Installation

``` r
library(ecoextract)

# Check that functions are available
?process_documents
?get_records
```

## Processing Documents

### The Four-Step Pipeline

[`process_documents()`](https://n8layman.github.io/ecoextract/reference/process_documents.md)
orchestrates a four-step extraction pipeline:

1.  **OCR Processing** (via ohseer) – Convert PDF to markdown text with
    embedded images
2.  **Metadata Extraction** – Extract publication metadata (title,
    authors, DOI, etc.)
3.  **Data Extraction** – Extract structured records using Claude
    according to your schema
4.  **Refinement** (optional) – Enhance and verify extracted data

### Quick Start

``` r
# Process a single PDF
results <- process_documents(
  pdf_path = "my_paper.pdf",
  db_conn = "ecoextract_records.db"
)

# Process all PDFs in a folder
results <- process_documents(
  pdf_path = "pdfs/",
  db_conn = "ecoextract_records.db"
)

# Process with refinement enabled
results <- process_documents(
  pdf_path = "pdfs/",
  db_conn = "ecoextract_records.db",
  run_refinement = TRUE
)
```

This automatically handles OCR, metadata extraction, data extraction
with Claude, saving to SQLite, and smart skip logic (re-running skips
completed steps).

### Parallel Processing

For faster processing of multiple documents, use parallel processing
with the `crew` package:

``` r
install.packages("crew")

# Process with 4 parallel workers
results <- process_documents(
  pdf_path = "pdfs/",
  db_conn = "ecoextract_records.db",
  workers = 4,
  log = TRUE  # Creates ecoextract_YYYYMMDD_HHMMSS.log
)
```

Benefits:

- Each worker processes a complete document (all 4 steps)
- Crash-resilient: completed documents saved immediately
- Progress shown as documents complete: `[1/10] paper.pdf completed`
- Re-run to resume: skip logic detects completed documents

### Skip Logic

When you re-run
[`process_documents()`](https://n8layman.github.io/ecoextract/reference/process_documents.md),
it automatically skips steps that have already completed. This allows
you to resume interrupted processing, add new PDFs, or re-run specific
steps after fixing issues.

#### Skip Behavior

Each step checks its status in the database:

| Step       | Skips When                                          |
|------------|-----------------------------------------------------|
| OCR        | `ocr_status = "completed"` AND markdown exists      |
| Metadata   | `metadata_status = "completed"` AND metadata exists |
| Extraction | `extraction_status = "completed"` AND records exist |
| Refinement | `refinement_status = "completed"` (opt-in only)     |

#### Cascade Logic

When a step is forced to re-run, downstream steps are automatically
invalidated:

| If This Re-runs | These Become Stale     |
|-----------------|------------------------|
| OCR             | Metadata, Extraction   |
| Metadata        | Extraction             |
| Extraction      | (nothing)              |
| Refinement      | (nothing, opt-in only) |

#### Force Reprocessing

Override skip logic to force reprocessing:

``` r
# Force reprocess all documents from OCR onward
results <- process_documents(
  pdf_path = "pdfs/",
  db_conn = "ecoextract_records.db",
  force_reprocess_ocr = TRUE
)

# Force reprocess specific documents only (by document_id)
results <- process_documents(
  pdf_path = "pdfs/",
  db_conn = "ecoextract_records.db",
  force_reprocess_extraction = c(5L, 12L)
)
```

Each `force_reprocess_*` parameter accepts:

- `NULL` (default) – use normal skip logic
- `TRUE` – force reprocess all documents
- Integer vector (e.g., `c(5L, 12L)`) – force reprocess specific
  document IDs

### Deduplication

During extraction, records are automatically deduplicated against
existing records in the database. Three similarity methods are
available:

``` r
# Default: LLM-based deduplication (most accurate)
results <- process_documents("pdfs/", db_conn = "records.db",
                            similarity_method = "llm")

# Embedding-based with custom threshold
results <- process_documents("pdfs/", db_conn = "records.db",
                            similarity_method = "embedding",
                            min_similarity = 0.85)

# Fast local deduplication (no API calls)
results <- process_documents("pdfs/", db_conn = "records.db",
                            similarity_method = "jaccard",
                            min_similarity = 0.9)
```

Methods:

- **`"llm"`** (default) – Uses Claude to semantically compare records
- **`"embedding"`** – Cosine similarity on text embeddings
- **`"jaccard"`** – Fast n-gram based comparison (no API calls)

## Customizing for Your Domain

EcoExtract is domain-agnostic. Customize it by editing the schema and
extraction prompt.

### Initialize Custom Configuration

``` r
# Creates ecoextract/ directory with template files
init_ecoextract()

# This creates:
# - ecoextract/SCHEMA_GUIDE.md      # Read this first!
# - ecoextract/schema.json          # Edit for your domain
# - ecoextract/extraction_prompt.md # Edit for your domain
```

Edit the files in `ecoextract/` for your research domain, then process
as usual – the package automatically detects configuration files in this
directory:

``` r
# Automatically uses ecoextract/schema.json and ecoextract/extraction_prompt.md
process_documents("pdfs/", "ecoextract_records.db")

# Or specify custom files explicitly
process_documents(
  pdf_path = "pdfs/",
  db_conn = "ecoextract_records.db",
  schema_file = "my_custom/schema.json",
  extraction_prompt_file = "my_custom/extraction.md"
)
```

For detailed guidance on writing schemas and prompts, see the
[Configuration
Guide](https://n8layman.github.io/ecoextract/articles/configuration.md).

## Retrieving Your Data

### Query Records

``` r
# Get all records from all documents
all_records <- get_records()

# Get records from a specific document
doc_records <- get_records(document_id = 1)

# Use a custom database path
records <- get_records(db_conn = "my_project.db")
```

### Query Documents

``` r
# Get all documents and their metadata
all_docs <- get_documents()

# Check processing status
all_docs$ocr_status          # "completed", "pending", "failed"
all_docs$metadata_status
all_docs$extraction_status
```

### Export Data

The
[`export_db()`](https://n8layman.github.io/ecoextract/reference/export_db.md)
function joins records with document metadata:

``` r
# Get all records with metadata as a tibble
data <- export_db()

# Export to CSV file
export_db(filename = "extracted_data.csv")

# Export only records from specific document
export_db(document_id = 1, filename = "document_1.csv")

# Include OCR content in export (large files!)
data <- export_db(include_ocr = TRUE)

# Simplified export (removes processing metadata columns)
data <- export_db(simple = TRUE)
```

The exported data includes document metadata (title, authors, journal,
DOI), all extracted record fields (defined by your schema), and
processing status with timestamps.

### View OCR Results

``` r
# Get OCR markdown text
markdown <- get_ocr_markdown(document_id = 1)
cat(markdown)

# View OCR with embedded images in RStudio Viewer
get_ocr_html_preview(document_id = 1)

# View all pages
get_ocr_html_preview(document_id = 1, page_num = "all")
```

## Human Review Workflow

After extraction, review and correct results using the **ecoreview**
Shiny app.

### Launch the Review App

``` r
library(ecoreview)
run_review_app(db_path = "ecoextract_records.db")
```

The app provides:

- **Document-by-document review** – Navigate through all processed
  documents
- **Side-by-side view** – See OCR text and extracted records together
- **Edit records** – Modify extracted data directly
- **Add records** – Manually add records the LLM missed
- **Delete records** – Remove incorrect records
- **Automatic audit trail** – All edits tracked in `record_edits` table

### Review Workflow

1.  **Process documents** with EcoExtract
2.  **Launch review app** with your database
3.  **Review each document** – check records against source text, edit,
    add, delete as needed, click “Accept”
4.  **Export final data** with corrections

### Edit Tracking

The
[`save_document()`](https://n8layman.github.io/ecoextract/reference/save_document.md)
function (used by ecoreview) tracks all changes:

- **Column-level edits** – Knows exactly which fields were changed
- **Original values** – Stores the LLM’s original extraction
- **Edit timestamps** – When each change was made
- **Added/deleted flags** – Distinguishes human-added vs LLM-extracted
  records

This audit trail enables accuracy calculations, understanding LLM
performance, and quality control.

For more information, see the [ecoreview
repository](https://github.com/n8layman/ecoreview).

### Calculate Accuracy Metrics

After reviewing documents, calculate comprehensive accuracy metrics:

``` r
accuracy <- calculate_accuracy("ecoextract_records.db")

# View key metrics
accuracy$detection_recall      # Did we find the records?
accuracy$field_precision       # How accurate were the fields?
accuracy$field_f1              # Overall field-level F1 score
accuracy$major_edit_rate       # How serious were the errors?
accuracy$avg_edits_per_document # Average corrections needed
```

EcoExtract provides nuanced accuracy metrics that separate:

- **Record detection** – Finding records vs missing/hallucinating them
- **Field-level accuracy** – Correctness of individual fields (gives
  partial credit)
- **Edit severity** – Major edits (unique/required fields) vs minor
  edits

For a complete explanation, see
[ACCURACY.md](https://n8layman.github.io/ecoextract/ACCURACY.md).
Accuracy visualizations are available in the
[ecoreview](https://github.com/n8layman/ecoreview) Shiny app.

## Complete Example

End-to-end workflow from processing through review and export:

``` r
library(ecoextract)

# 1. Initialize custom configuration (first time only)
init_ecoextract()
# Edit ecoextract/schema.json and ecoextract/extraction_prompt.md

# 2. Process documents with parallel processing
results <- process_documents(
  pdf_path = "papers/",
  db_conn = "records.db",
  workers = 4,
  log = TRUE
)

# 3. Launch review app
library(ecoreview)
run_review_app(db_path = "records.db")
# Review and edit records in the Shiny app

# 4. Export final data
final_data <- export_db(
  db_conn = "records.db",
  filename = "final_data.csv"
)

# 5. Check results
library(dplyr)
edited_records <- final_data |> filter(human_edited == TRUE)
cat("Total records:", nrow(final_data), "\n")
cat("Edited records:", nrow(edited_records), "\n")

# 6. Calculate accuracy
accuracy <- calculate_accuracy("records.db")
```

## Database Schema

The SQLite database has two main tables:

**documents** – Stores document metadata and processing status:

- `document_id`, `file_name`, `file_path` – Identity
- `title`, `authors`, `publication_year`, `journal`, `doi` – Publication
  metadata
- `document_content` – OCR markdown text
- `ocr_status`, `metadata_status`, `extraction_status`,
  `refinement_status` – Processing status
- `records_extracted` – Count of records extracted

**records** – Stores extracted data records:

- `id` – Primary key (auto-increment)
- `document_id` – Foreign key to documents
- `record_id` – Human-readable identifier (e.g., “Smith2023-001”)
- Custom fields defined by your schema
- `extraction_timestamp`, `llm_model_version` – Metadata

**record_edits** – Audit trail for human edits:

- Tracks column-level changes with original values and timestamps

## Best Practices

**Start small.** Test on 2-3 papers first. Review results before
processing an entire corpus.

**Use parallel processing for large batches.** For 10+ papers,
`workers = 4` significantly speeds up processing.

**Enable refinement selectively.** Run refinement only on documents that
need it: `run_refinement = c(5L, 12L, 18L)`.

**Review early and often.** Process a small batch, review immediately
with ecoreview, then iterate on your schema and prompts before
processing more.

**Version control your configs.** Add `ecoextract/schema.json` and
`ecoextract/extraction_prompt.md` to git. Keep `.env` (API keys) in
`.gitignore`.

**Monitor API usage.** Track usage at <https://console.anthropic.com/>.
Typical per-paper usage: OCR ~2-5K tokens, metadata ~1-2K, extraction
~5-10K, refinement ~3-5K.

## Troubleshooting

### API Key Not Found

``` r
# Reload from .env file
readRenviron(".env")

# Or set directly
Sys.setenv(ANTHROPIC_API_KEY = "sk-ant-...")

# Verify
Sys.getenv("ANTHROPIC_API_KEY")
```

### Database Locked Errors

If you get “database is locked” during parallel processing, this usually
resolves automatically. Verify WAL mode is enabled:

``` r
library(DBI)
db <- dbConnect(RSQLite::SQLite(), "records.db")
dbGetQuery(db, "PRAGMA journal_mode")  # Should return "wal"
dbGetQuery(db, "PRAGMA busy_timeout")  # Should return 30000
dbDisconnect(db)
```

### Schema Validation Errors

``` r
# Validate JSON syntax
jsonlite::validate("ecoextract/schema.json")

# Verify structure (must have top-level "records" property)
schema <- jsonlite::read_json("ecoextract/schema.json")
names(schema$properties)  # Should include "records"

# Test with default schema first
process_documents("test.pdf", "test.db", schema_file = NULL)
```

### OCR Failures

``` r
# Check which documents failed
docs <- get_documents()
failed <- docs |> dplyr::filter(ocr_status == "failed")

# Force reprocess failed OCR
process_documents(
  pdf_path = "pdfs/",
  db_conn = "records.db",
  force_reprocess_ocr = failed$document_id
)
```

## Next Steps

- **[Configuration
  Guide](https://n8layman.github.io/ecoextract/articles/configuration.md)**
  – Customize schema and prompts for your domain
- **[Testing
  Guide](https://n8layman.github.io/ecoextract/articles/testing.md)** –
  Running and writing tests
- **[ACCURACY.md](https://n8layman.github.io/ecoextract/ACCURACY.md)** –
  Understanding accuracy metrics in depth
- **Function docs**:
  [`?process_documents`](https://n8layman.github.io/ecoextract/reference/process_documents.md),
  [`?get_records`](https://n8layman.github.io/ecoextract/reference/get_records.md),
  [`?export_db`](https://n8layman.github.io/ecoextract/reference/export_db.md),
  [`?calculate_accuracy`](https://n8layman.github.io/ecoextract/reference/calculate_accuracy.md)
- **Repos**: [ecoextract](https://github.com/n8layman/ecoextract) \|
  [ecoreview](https://github.com/n8layman/ecoreview) \|
  [ohseer](https://github.com/n8layman/ohseer)
