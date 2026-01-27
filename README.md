# EcoExtract

Structured ecological data extraction and refinement from scientific literature.

**Package Links:**

- [ecoextract on GitHub](https://github.com/n8layman/ecoextract)
- [ohseer on GitHub](https://github.com/n8layman/ohseer) (OCR dependency)

## Installation

### Prerequisites

First, install the required `ohseer` package for OCR processing:

```r
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

```r
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

EcoExtract uses [ellmer](https://ellmer.tidyverse.org/) for LLM interactions. OCR processing via [ohseer](https://github.com/n8layman/ohseer) currently requires Mistral AI.

### Getting API Keys

Required:

- Mistral AI (for OCR): <https://console.mistral.ai/>

Recommended for data extraction:

- Anthropic Claude: <https://console.anthropic.com/>

Note: While ecoextract is designed to work with any ellmer-supported LLM provider (OpenAI, etc.), this has not been fully tested. Mistral AI is currently hardcoded for OCR processing.

### Setting Up API Keys

**IMPORTANT: Before creating your `.env` file, verify it's gitignored:**

```bash
# Check that .env is in .gitignore
grep "^\.env$" .gitignore

# If not found, add it NOW before creating the file:
echo ".env" >> .gitignore
```

Create a `.env` file in the project root directory:

```bash
# .env
ANTHROPIC_API_KEY=your_anthropic_api_key_here
MISTRAL_API_KEY=your_mistral_api_key_here

# Or use other providers supported by ellmer
OPENAI_API_KEY=your_openai_api_key_here
# ... etc
```

**Verify before committing:**

```bash
# This should show no output if .env is properly ignored:
git status | grep ".env"

# If .env appears, do NOT commit! Add it to .gitignore first.
```

**The `.env` file is automatically loaded** when you start R in this project directory (via `.Rprofile`). Just restart your R session after creating the file.

Alternatively, load manually:

```r
# Option 1: Use readRenviron for a specific file
readRenviron(".env")

# Option 2: Set directly in R
Sys.setenv(ANTHROPIC_API_KEY = "your_key_here")
```

### Using Different LLM Providers

By default, ecoextract uses `anthropic/claude-sonnet-4-5` for data extraction, metadata, and refinement. If you have an Anthropic API key set up, no additional configuration is needed.

To use a different LLM provider, pass the `model` parameter:

```r
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

```r
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

print(results)

# Process a single PDF
results <- process_documents(
  pdf_path = "paper.pdf",
  db_conn = "ecoextract_records.db"
)

# Use custom schema and extraction prompt
results <- process_documents(
  pdf_path = "path/to/pdfs/",
  db_conn = "ecoextract_records.db",
  schema_file = "custom_schema.json",
  extraction_prompt_file = "custom_extraction_prompt.md"
)

# Run with refinement enabled
results <- process_documents(
  pdf_path = "path/to/pdfs/",
  db_conn = "ecoextract_records.db",
  run_refinement = TRUE
)

# Force reprocess all documents from OCR onward
results <- process_documents(
  pdf_path = "path/to/pdfs/",
  db_conn = "ecoextract_records.db",
  force_reprocess_ocr = TRUE
)

# Force reprocess specific documents only
results <- process_documents(
  pdf_path = "path/to/pdfs/",
  db_conn = "ecoextract_records.db",
  force_reprocess_extraction = c(5L, 12L)
)
```

For advanced use cases requiring individual step processing, see the package documentation.

## Skip and Cascade Logic

By default, `process_documents()` skips steps that have already completed successfully. Each step checks its status in the database and verifies that output data exists before skipping.

When a step is re-run (forced or due to missing data), downstream steps are automatically invalidated:

| If This Re-runs | These Become Stale       |
| --------------- | ------------------------ |
| OCR             | Metadata, Extraction     |
| Metadata        | Extraction               |
| Extraction      | (nothing)                |
| Refinement      | (nothing, opt-in only)   |

### Force Reprocess Parameters

Each `force_reprocess_*` parameter accepts three values:

- `NULL` (default) -- use normal skip logic
- `TRUE` -- force reprocess all documents
- Integer vector (e.g., `c(5L, 12L)`) -- force reprocess specific document IDs

The `run_refinement` parameter works the same way: `NULL` skips refinement, `TRUE` runs on all documents with records, or an integer vector targets specific documents.

See [SKIP_LOGIC.md](SKIP_LOGIC.md) for full details.

## Deduplication

During extraction, records are deduplicated against existing records in the database to prevent duplicates. Three similarity methods are available:

- **`"llm"`** (default) -- Uses Claude to semantically compare records. Most accurate but uses API calls.
- **`"embedding"`** -- Cosine similarity on text embeddings. Requires an embedding provider (default: OpenAI).
- **`"jaccard"`** -- Fast n-gram based comparison. No API calls needed.

Configure via `process_documents()`:

```r
# Default: LLM-based deduplication
results <- process_documents("pdfs/", similarity_method = "llm")

# Embedding-based with custom threshold
results <- process_documents("pdfs/", similarity_method = "embedding", min_similarity = 0.85)

# Fast local deduplication
results <- process_documents("pdfs/", similarity_method = "jaccard", min_similarity = 0.9)
```

## Custom Schemas

EcoExtract is domain-agnostic and works with any JSON schema. The package includes a bat-plant interaction schema as an example, but you can define custom schemas for any ecological domain (disease outbreaks, species observations, etc.).

### Initialize Custom Configuration

To customize the schema and prompts for your project:

```r
# Create ecoextract/ directory with template files
library(ecoextract)
init_ecoextract()

# This creates:
# - ecoextract/SCHEMA_GUIDE.md      # Read this first!
# - ecoextract/schema.json          # Edit for your domain
# - ecoextract/extraction_prompt.md # Edit for your domain
```

Now edit the files in `ecoextract/` to customize for your domain:

1. **Read `SCHEMA_GUIDE.md`** to understand the required schema format
2. Edit `schema.json` to define your data structure
3. Edit `extraction_prompt.md` to describe what to extract

The package will automatically detect and use these files when you run `process_documents()`.

**Priority order for loading configs:**

1. Explicit file path passed to function (e.g., `schema_file = "path/to/schema.json"`)
2. Project `ecoextract/` directory (e.g., `ecoextract/schema.json`)
3. Working directory with `ecoextract_` prefix (e.g., `ecoextract_schema.json`)
4. Package defaults from `inst/extdata/` and `inst/prompts/`

### Schema Requirements

Your schema MUST follow this structure:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Your Domain Schema",
  "description": "Schema for extracting your domain-specific data",
  "type": "object",
  "properties": {
    "records": {
      "type": "array",
      "description": "Your domain-specific records",
      "items": {
        "type": "object",
        "properties": {
          "your_field_1": { "type": "string", "description": "..." },
          "your_field_2": { "type": "integer", "description": "..." },
          "location": { "type": "string", "description": "..." },
          "observation_date": { "type": "string", "description": "..." }
          // ... add your custom fields here
        }
      }
    }
  },
  "required": ["records"]
}
```

**Key requirements:**

1. Top-level must have a `records` property (array of objects)
2. Each field should have a `type` and `description` (description helps the LLM understand what to extract)
3. Use JSON Schema draft-07 format
4. Record IDs are auto-generated from publication metadata (extracted in the metadata step)

See [`inst/extdata/schema.json`](inst/extdata/schema.json) for a complete example.

## Package Functions

### Workflow

- `process_documents()` - Complete 4-step workflow (OCR -> Metadata -> Extract -> Refine)

### Database Setup

- `init_ecoextract_database()` - Initialize database with schema
- `init_ecoextract()` - Create project config directory with template schema and prompts

### Data Access

- `get_documents()` - Query documents and their metadata from database
- `get_records()` - Query extracted records from database
- `get_ocr_markdown()` - Get OCR markdown text for a document
- `get_ocr_html_preview()` - Render OCR output with embedded images as HTML
- `get_db_stats()` - Get document and record counts from database
- `export_db()` - Export records with metadata to tibble or CSV file

## Testing

```r
# Run all tests
devtools::test()

# Run package checks
devtools::check()
```

### Integration Tests

Integration tests verify API interactions with LLM providers. To run these locally, set up API keys in a `.env` file (see API Key Setup above). The tests will automatically load `.env` files, or you can load them manually:

```r
library(ecoextract)
devtools::test()
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for more details on testing and development workflow.

## File Structure

```text
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
├── SKIP_LOGIC.md           # Skip/cascade logic documentation
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

- Mistral AI - OCR processing (via ohseer)
- Anthropic Claude / OpenAI / other LLM providers - Data extraction and refinement (via ellmer)

## License

MIT License
