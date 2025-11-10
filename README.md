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
# Option 1: Use ecoextract's load_env() function (loads all .env* files)
library(ecoextract)
load_env()

# Option 2: Use readRenviron for a specific file
readRenviron(".env")

# Option 3: Set directly in R
Sys.setenv(ANTHROPIC_API_KEY = "your_key_here")
```

### Using Different LLM Providers

By default, ecoextract uses `anthropic/claude-sonnet-4-20250514` for data extraction and refinement. If you have an Anthropic API key set up, no additional configuration is needed.

To use a different LLM provider, pass the `model` parameter:

```r
# Default (Anthropic Claude) - no model parameter needed
results <- process_documents(
  pdf_path = "path/to/pdfs/",
  db_conn = "ecological_records.sqlite"
)

# Use a different model (experimental - not fully tested)
results <- process_documents(
  pdf_path = "path/to/pdfs/",
  db_conn = "ecological_records.sqlite",
  model = "openai/gpt-4"
)
```

## Quick Start

```r
library(ecoextract)

# Process all PDFs in a folder through complete 4-step workflow:
# 1. OCR (extract text from PDF)
# 2. Document Audit (extract metadata + review OCR quality)
# 3. Extraction (extract domain-specific records)
# 4. Refinement (refine and validate records)
results <- process_documents(
  pdf_path = "path/to/pdfs/",
  db_conn = "ecological_records.sqlite"
)

print(results)

# Process a single PDF
results <- process_documents(
  pdf_path = "paper.pdf",
  db_conn = "ecological_records.sqlite"
)

# Use custom schema and prompts
results <- process_documents(
  pdf_path = "path/to/pdfs/",
  db_conn = "ecological_records.sqlite",
  schema_file = "custom_schema.json",
  extraction_prompt_file = "custom_extraction_prompt.md",
  refinement_prompt_file = "custom_refinement_prompt.md"
)

# Force reprocess existing documents
results <- process_documents(
  pdf_path = "path/to/pdfs/",
  db_conn = "ecological_records.sqlite",
  force_reprocess = TRUE
)
```

For advanced use cases requiring individual step processing, see the package documentation.

## Custom Schemas

EcoExtract is domain-agnostic and works with any JSON schema. The package includes a bat-plant interaction schema as an example, but you can define custom schemas for any ecological domain (disease outbreaks, species observations, etc.).

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
4. Occurrence IDs are auto-generated from publication metadata (extracted in document_audit step)

See [`inst/extdata/schema.json`](inst/extdata/schema.json) for a complete example.

## Package Functions

### Workflow

- `process_documents()` - Complete 4-step workflow (OCR → Audit → Extract → Refine)
- `ocr_document()` - Step 1: Extract text from PDF
- `audit_document()` - Step 2: Extract metadata + review OCR quality
- `extract_records()` - Step 3: Extract domain-specific records
- `refine_records()` - Step 4: Refine and validate records

### Database Operations

- `init_ecoextract_database()` - Initialize database with schema
- `get_document_content()` - Get OCR text from database
- `get_ocr_audit()` - Get OCR audit from database
- `get_records()` - Get extracted records from database

### Custom Configuration

- Schema files in `inst/extdata/`: `schema.json`, `document_audit_schema.json`
- Prompt files in `inst/prompts/`: extraction, refinement, document audit prompts

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
load_env()
devtools::test()
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for more details on testing and development workflow.

## File Structure

```
ecoextract/
├── R/
│   ├── workflow.R          # Main process_documents() workflow
│   ├── ocr.R               # OCR processing
│   ├── document_audit.R    # Metadata extraction & OCR quality review
│   ├── extraction.R        # Data extraction functions
│   ├── refinement.R        # Data refinement functions
│   ├── database.R          # Database operations
│   ├── schema.R            # Schema validation
│   ├── prompts.R           # Prompt loading
│   ├── getters.R           # Getter functions for DB
│   ├── config_loader.R     # Configuration file loading
│   └── utils.R             # Utilities
├── inst/
│   ├── extdata/            # Schema files
│   │   ├── schema.json
│   │   └── document_audit_schema.json
│   └── prompts/            # System prompts
│       ├── extraction_prompt.md
│       ├── extraction_context.md
│       ├── refinement_prompt.md
│       ├── refinement_context.md
│       ├── document_audit_prompt.md
│       └── document_audit_context.md
├── tests/testthat/         # Tests
├── DESCRIPTION
├── NAMESPACE
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
- `stringr` - String manipulation
- `digest` - Hashing

### External APIs

- Mistral AI - OCR processing (via ohseer)
- Anthropic Claude / OpenAI / other LLM providers - Data extraction and refinement (via ellmer)

## License

MIT License
