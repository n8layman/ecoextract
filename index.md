# EcoExtract

Structured ecological data extraction and refinement from scientific
literature.

EcoExtract automates the extraction of structured data from PDFs using
OCR and LLMs. It’s domain-agnostic and works with any JSON schema you
define.

**Quick Links:**

- [Documentation](https://n8layman.github.io/ecoextract/) (GitHub Pages)
- [Getting
  Started](https://n8layman.github.io/ecoextract/articles/getting-started.html)
- [Full
  Tutorial](https://n8layman.github.io/ecoextract/articles/ecoextract-workflow.html)
  (Comprehensive vignette)
- [Configuration
  Guide](https://n8layman.github.io/ecoextract/articles/configuration.html)
- [Accuracy Metrics
  Guide](https://n8layman.github.io/ecoextract/ACCURACY.md)
  (Understanding accuracy calculations)
- [ecoreview on GitHub](https://github.com/n8layman/ecoreview) (Review
  Shiny app)
- [ohseer on GitHub](https://github.com/n8layman/ohseer) (OCR
  dependency)

## Installation

### Prerequisites

First, install the required `ohseer` package for OCR processing:

``` r
# Option 1: Using pak (recommended)
pak::pak("n8layman/ohseer")

# Option 2: Using devtools
devtools::install_github("n8layman/ohseer")

# Option 3: Using remotes
remotes::install_github("n8layman/ohseer")

# Option 4: Using renv
renv::install("n8layman/ohseer")
```

### Install ecoextract

``` r
# Option 1: Using pak (recommended)
pak::pak("n8layman/ecoextract")

# Option 2: Using devtools
devtools::install_github("n8layman/ecoextract")

# Option 3: Using remotes
remotes::install_github("n8layman/ecoextract")

# Option 4: Using renv
renv::install("n8layman/ecoextract")

# Then load the library
library(ecoextract)
```

## API Key Setup

EcoExtract uses [ellmer](https://ellmer.tidyverse.org/) for LLM
interactions. OCR processing via
[ohseer](https://github.com/n8layman/ohseer) uses Tensorlake.

### Getting API Keys

Required:

- Tensorlake (for OCR): <https://www.tensorlake.ai/>

Recommended for data extraction:

- Anthropic Claude: <https://console.anthropic.com/>

Note: While ecoextract is designed to work with any ellmer-supported LLM
provider (OpenAI, etc.), this has not been fully tested.

### Setting Up API Keys

**IMPORTANT: Before creating your `.env` file, verify it’s gitignored:**

``` bash
# Check that .env is in .gitignore
grep "^\.env$" .gitignore

# If not found, add it NOW before creating the file:
echo ".env" >> .gitignore
```

Create a `.env` file in the project root directory:

``` bash
# .env
ANTHROPIC_API_KEY=your_anthropic_api_key_here
TENSORLAKE_API_KEY=your_tensorlake_api_key_here

# Or use other providers supported by ellmer
OPENAI_API_KEY=your_openai_api_key_here
# ... etc
```

**Verify before committing:**

``` bash
# This should show no output if .env is properly ignored:
git status | grep ".env"

# If .env appears, do NOT commit! Add it to .gitignore first.
```

**The `.env` file is automatically loaded** when you start R in this
project directory (via `.Rprofile`). Just restart your R session after
creating the file.

Alternatively, load manually:

``` r
# Option 1: Use readRenviron for a specific file
readRenviron(".env")

# Option 2: Set directly in R
Sys.setenv(ANTHROPIC_API_KEY = "your_key_here")
```

### Using Different LLM Providers

By default, ecoextract uses `anthropic/claude-sonnet-4-5` for data
extraction, metadata, and refinement. If you have an Anthropic API key
set up, no additional configuration is needed.

To use a different LLM provider, pass the `model` parameter:

``` r
# Default (Anthropic Claude) - no model parameter needed
results <- process_documents(
  pdf_path = "path/to/pdfs/",
  db_conn = "ecoextract_records.db"
)

# Use a different model (experimental - not fully tested)
results <- process_documents(
  pdf_path = "path/to/pdfs/",
  db_conn = "ecoextract_records.db",
  model = "openai/gpt-4"
)
```

## Quick Start

``` r
library(ecoextract)

# Process all PDFs in a folder through complete 4-step workflow:
# 1. OCR (extract text from PDF)
# 2. Metadata (extract publication metadata)
# 3. Extraction (extract domain-specific records)
# 4. Refinement (refine and validate records, opt-in)
results <- process_documents(
  pdf_path = "path/to/pdfs/",
  db_conn = "ecoextract_records.db"
)

# Retrieve your data
records <- get_records()
export_db(filename = "extracted_data.csv")
```

**See the
[vignette](https://n8layman.github.io/ecoextract/articles/ecoextract-workflow.html)
for:**

- Parallel processing with multiple workers
- Custom schemas and prompts
- Skip logic and force reprocessing
- Data retrieval and export options
- Complete workflow examples

## Key Features

### Smart Skip Logic

Re-running
[`process_documents()`](https://n8layman.github.io/ecoextract/reference/process_documents.md)
automatically skips completed steps. When a step is forced to re-run,
downstream steps are automatically invalidated.

See the
[vignette](https://n8layman.github.io/ecoextract/articles/ecoextract-workflow.html)
for details.

### Parallel Processing

Process multiple documents in parallel using the `crew` package:

``` r
install.packages("crew")

results <- process_documents(
  pdf_path = "papers/",
  db_conn = "records.db",
  workers = 4,
  log = TRUE
)
```

Crash-resilient with automatic resume capability. See the
[vignette](https://n8layman.github.io/ecoextract/articles/ecoextract-workflow.html)
for details.

### Deduplication

Three similarity methods available: `"llm"` (default), `"embedding"`, or
`"jaccard"`. See the
[vignette](https://n8layman.github.io/ecoextract/articles/ecoextract-workflow.html)
for details.

## Custom Schemas

EcoExtract is domain-agnostic and works with any JSON schema:

``` r
# Create custom config directory with templates
init_ecoextract()

# Edit the generated files:
# - ecoextract/schema.json          # Define your data structure
# - ecoextract/extraction_prompt.md # Describe what to extract

# The package automatically uses these files
process_documents("pdfs/", "records.db")
```

**Schema Requirements:**

- Top-level must have a `records` property (array of objects)
- Each field needs `type` and `description`
- Use JSON Schema draft-07 format

See the
[vignette](https://n8layman.github.io/ecoextract/vignettes/ecoextract-workflow.Rmd)
and `ecoextract/SCHEMA_GUIDE.md` for complete details and examples.

## Data Retrieval

After processing documents, use these functions to retrieve and export
your data:

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

# Get a specific document
doc <- get_documents(document_id = 1)

# Check processing status
doc$ocr_status          # "completed", "pending", "failed"
doc$metadata_status     # "completed", "pending", "failed"
doc$extraction_status   # "completed", "pending", "failed"
```

### Export Data

The
[`export_db()`](https://n8layman.github.io/ecoextract/reference/export_db.md)
function joins records with document metadata for easy export:

``` r
# Get all records with metadata as a tibble
data <- export_db()

# Export to CSV file
export_db(filename = "extracted_data.csv")

# Export only records from specific document
export_db(document_id = 1, filename = "document_1.csv")

# Include OCR text in export (large files!)
data <- export_db(include_ocr = TRUE)

# Simplified export (removes processing metadata columns)
data <- export_db(simple = TRUE)
```

The exported data includes:

- Document metadata (title, authors, journal, DOI, etc.)
- All extracted record fields (defined by your schema)
- Processing status and timestamps

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

### Database Statistics

``` r
# Get summary counts
get_db_stats()
# Returns: documents_count, records_count, documents_with_records
```

## Human Review Workflow

After extraction, you can review and edit records using the
**ecoreview** Shiny application:

### Install ecoreview

``` r
# Install from GitHub
pak::pak("n8layman/ecoreview")
```

### Launch Review App

``` r
library(ecoreview)

# Launch the review app with your database
run_review_app(db_path = "ecoextract_records.db")
```

The review app provides:

- Document-by-document review interface
- Side-by-side view of OCR text and extracted records
- Edit records directly in the app
- Add new records manually
- Delete incorrect records
- Automatic edit tracking and audit trail (stored in `record_edits`
  table)
- Accuracy calculation based on edits

All edits are saved to the database using
[`save_document()`](https://n8layman.github.io/ecoextract/reference/save_document.md),
which tracks:

- Which columns were modified
- Original values before edits
- Edit timestamps
- Records added or deleted by humans

For more information, see the [ecoreview
repository](https://github.com/n8layman/ecoreview).

### Calculate Accuracy Metrics

After reviewing documents, calculate comprehensive accuracy metrics:

``` r
# Calculate accuracy for all verified documents
accuracy <- calculate_accuracy("ecoextract_records.db")

# View key metrics
accuracy$detection_recall      # Did we find the records?
accuracy$field_precision       # How accurate were the fields?
accuracy$major_edit_rate       # How serious were the errors?
accuracy$avg_edits_per_document # Average corrections needed
```

EcoExtract provides nuanced accuracy metrics that separate: - **Record
detection**: Finding records vs missing/hallucinating them -
**Field-level accuracy**: Correctness of individual fields (gives
partial credit) - **Edit severity**: Major edits (unique/required
fields) vs minor edits

For a complete explanation of how accuracy is calculated and
interpreted, see
[ACCURACY.md](https://n8layman.github.io/ecoextract/ACCURACY.md).

Accuracy visualizations (confusion matrices, heatmaps) are available in
[ecoreview](https://github.com/n8layman/ecoreview).

## Package Functions

### Workflow

- [`process_documents()`](https://n8layman.github.io/ecoextract/reference/process_documents.md) -
  Complete 4-step workflow (OCR -\> Metadata -\> Extract -\> Refine)

### Database Setup

- [`init_ecoextract_database()`](https://n8layman.github.io/ecoextract/reference/init_ecoextract_database.md) -
  Initialize database with schema
- [`init_ecoextract()`](https://n8layman.github.io/ecoextract/reference/init_ecoextract.md) -
  Create project config directory with template schema and prompts

### Data Access

- [`get_documents()`](https://n8layman.github.io/ecoextract/reference/get_documents.md) -
  Query documents and their metadata from database
- [`get_records()`](https://n8layman.github.io/ecoextract/reference/get_records.md) -
  Query extracted records from database
- [`get_ocr_markdown()`](https://n8layman.github.io/ecoextract/reference/get_ocr_markdown.md) -
  Get OCR markdown text for a document
- [`get_ocr_html_preview()`](https://n8layman.github.io/ecoextract/reference/get_ocr_html_preview.md) -
  Render OCR output with embedded images as HTML
- [`get_db_stats()`](https://n8layman.github.io/ecoextract/reference/get_db_stats.md) -
  Get document and record counts from database
- [`export_db()`](https://n8layman.github.io/ecoextract/reference/export_db.md) -
  Export records with metadata to tibble or CSV file

## Testing

``` r
# Run all tests
devtools::test()

# Run package checks
devtools::check()
```

### Integration Tests

Integration tests verify API interactions with LLM providers. To run
these locally, set up API keys in a `.env` file (see API Key Setup
above). The tests will automatically load `.env` files, or you can load
them manually:

``` r
library(ecoextract)
devtools::test()
```

See
[CONTRIBUTING.md](https://n8layman.github.io/ecoextract/CONTRIBUTING.md)
for more details on testing and development workflow.

## File Structure

``` text
ecoextract/
├── R/
│   ├── workflow.R          # Main process_documents() workflow + skip/cascade logic
│   ├── ocr.R               # OCR processing
│   ├── metadata.R          # Publication metadata extraction
│   ├── extraction.R        # Data extraction functions
│   ├── refinement.R        # Data refinement functions
│   ├── deduplication.R     # Record deduplication (LLM, embedding, Jaccard)
│   ├── database.R          # Database operations
│   ├── getters.R           # Data access functions (get_*, export_db)
│   ├── config_loader.R     # Configuration file loading + init_ecoextract()
│   ├── prompts.R           # Prompt loading
│   ├── utils.R             # Utilities
│   ├── config.R            # Package configuration
│   └── ecoextract-package.R # Package metadata
├── inst/
│   ├── extdata/            # Schema files
│   │   ├── schema.json
│   │   └── metadata_schema.json
│   └── prompts/            # System prompts
│       ├── extraction_prompt.md
│       ├── extraction_context.md
│       ├── metadata_prompt.md
│       ├── metadata_context.md
│       ├── refinement_prompt.md
│       ├── refinement_context.md
│       └── deduplication_prompt.md
├── tests/testthat/         # Tests
├── vignettes/              # Package vignettes
├── DESCRIPTION
├── NAMESPACE
├── CONTRIBUTING.md         # Development guide
└── README.md
```

## Tech Stack

### R Packages

- [`ellmer`](https://ellmer.tidyverse.org/) - Structured LLM outputs
- [`ohseer`](https://github.com/n8layman/ohseer) - OCR processing
- `dplyr` - Data manipulation
- `DBI` & `RSQLite` - Database operations
- `jsonlite` - JSON handling
- `glue` - String interpolation
- `stringr` & `stringi` - String manipulation
- `digest` - Hashing
- `tidyllm` - LLM deduplication

### External APIs

- Tensorlake - OCR processing (via ohseer)
- Anthropic Claude / OpenAI / other LLM providers - Data extraction and
  refinement (via ellmer)

## License

MIT License
