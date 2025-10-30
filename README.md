# EcoExtract

Structured ecological data extraction and refinement from scientific literature.

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
```

### Development Installation (Local)

```r
# Load locally during development
devtools::load_all("./ecoextract")
```

### Production Installation (GitHub)

```r
# Install from GitHub (when package has its own repository)
devtools::install_github("yourorg/ecoextract")

# Modern alternatives
pak::pkg_install("yourorg/ecoextract")
renv::install("yourorg/ecoextract")

# Then load the library
library(ecoextract)
```

## API Key Setup

EcoExtract uses [ellmer](https://ellmer.tidyverse.org/) for LLM interactions, which supports any LLM provider that ellmer supports (Anthropic, OpenAI, Mistral, etc.). By default, examples use Anthropic's Claude and Mistral for OCR processing.

### Getting API Keys

Examples in this README use:
- Anthropic Claude: https://console.anthropic.com/
- Mistral (for OCR): https://console.mistral.ai/

You can use any provider supported by ellmer - see [ellmer documentation](https://ellmer.tidyverse.org/) for full provider list.

### Setting Up API Keys

Create a `.env` file in your project directory:

```bash
# .env
ANTHROPIC_API_KEY=your_anthropic_api_key_here
MISTRAL_API_KEY=your_mistral_api_key_here

# Or use other providers supported by ellmer
OPENAI_API_KEY=your_openai_api_key_here
# ... etc
```

**Important:** The `.env` file is gitignored by default. Never commit API keys to version control.

Load environment variables in R:

```r
# Option 1: Use dotenv package to load from .env file (recommended)
# install.packages("dotenv")
dotenv::load_dot_env()

# Option 2: Set them directly in R
Sys.setenv(ANTHROPIC_API_KEY = "your_key_here")
Sys.setenv(MISTRAL_API_KEY = "your_key_here")
```

### Using Different LLM Providers

Specify the model using the `model` parameter in `extract_records()` and `refine_records()`:

```r
# Use OpenAI
extraction_result <- extract_records(
  document_content = ocr_text,
  model = "openai/gpt-4"
)

# Use Anthropic Claude (default)
extraction_result <- extract_records(
  document_content = ocr_text,
  model = "anthropic/claude-sonnet-4-20250514"
)
```

## Quick Start

### Process a Folder of PDFs

```r
library(ecoextract)

# Process all PDFs in a folder
results <- process_ecological_documents(
  pdf_folder = "path/to/pdfs/",
  output_db = "ecological_interactions.sqlite"
)

print(results)
```

### Individual Document Processing

```r
# Extract interactions from OCR text
extraction_result <- extract_records(
  markdown_text = your_ocr_text,
  ocr_audit = quality_analysis
)

# Refine the extracted interactions  
refinement_result <- refine_records(
  interactions = extraction_result$interactions,
  markdown_text = your_ocr_text,
  ocr_audit = quality_analysis
)
```

## Database Operations

```r
# Initialize a new database
init_ecoextract_database("my_results.sqlite")

# Get database statistics
stats <- get_db_stats("my_results.sqlite")
print(stats)
```

## Custom Schemas

EcoExtract is domain-agnostic and works with any JSON schema. The package includes a bat-plant interaction schema as an example, but you can define custom schemas for any ecological domain (disease outbreaks, species observations, etc.).

### Schema Requirements

Your schema MUST follow this structure:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "publication_metadata": {
      "type": "object",
      "properties": {
        "first_author_lastname": { "type": "string" },
        "publication_year": { "type": "integer" }
      }
    },
    "records": {
      "type": "array",
      "description": "Your domain-specific records",
      "items": {
        "type": "object",
        "properties": {
          "occurrence_id": { "type": "string" },
          // ... your custom fields here
        }
      }
    }
  },
  "required": ["records"]
}
```

**Key requirements:**
1. Top-level must have a `records` property (array of objects)
2. `publication_metadata` with `first_author_lastname` and `publication_year` is recommended for occurrence ID generation
3. Each record should have an `occurrence_id` field (or one will be auto-generated)
4. Use JSON Schema draft-07 format

See [`inst/extdata/schema.json`](inst/extdata/schema.json) for a complete example.

## Schema Validation

```r
# Validate your data against the schema
validation <- validate_interactions_schema(your_data)

if (!validation$valid) {
  print(validation$errors)
}

# Get schema information
schema_info <- get_database_schema()
print(schema_info$columns)
```

## Package Functions

### Core Processing
- `process_ecological_documents()` - Batch process PDFs
- `extract_records()` - Extract structured records from markdown
- `refine_records()` - Refine extracted records
- `perform_ocr_audit()` - Check OCR output for errors

### Database Operations
- `init_ecoextract_database()` - Initialize database with schema
- `save_document_to_db()` - Save document metadata
- `save_records_to_db()` - Save extracted records
- `get_db_stats()` - Get database statistics

### Schema & Validation
- `validate_interactions_schema()` - Validate data against schema
- `get_database_schema()` - Get schema information
- `filter_to_schema_columns()` - Filter data to schema columns

### Prompts
- `get_extraction_prompt()` - Get extraction prompt
- `get_refinement_prompt()` - Get refinement prompt
- `get_ocr_audit_prompt()` - Get OCR audit prompt
- `get_extraction_context_template()` - Get context template

### Utilities
- `generate_occurrence_id()` - Generate unique occurrence IDs
- `add_occurrence_ids()` - Add IDs to dataframe
- `merge_refinements()` - Merge refined data back

## Testing

```r
# Run all tests
devtools::test()

# Run package checks
devtools::check()
```

### Integration Tests

Integration tests verify API interactions with LLM providers. To run these locally, set up API keys in a `.env` file (see API Key Setup above) and load them before testing:

```r
dotenv::load_dot_env()
devtools::test()
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for more details on testing and development workflow.

## File Structure

```
ecoextract/
├── R/
│   ├── extraction.R        # Data extraction functions
│   ├── refinement.R        # Data refinement functions  
│   ├── schema.R            # Schema validation
│   ├── enrichment.R        # Metadata enrichment
│   ├── database.R          # Database operations
│   ├── prompts.R           # Prompt management
│   ├── config.R            # Configuration & API keys
│   └── utils.R             # Main CLI and utilities
├── inst/
│   └── prompts/            # System prompts
│       ├── extraction_prompt.md
│       ├── refinement_prompt.md
│       └── extraction_context.md
├── DESCRIPTION
├── NAMESPACE
└── README.md
```

## Dependencies

- `dplyr` - Data manipulation
- `readr` - File reading
- `stringr` - String manipulation
- `glue` - String interpolation
- `jsonlite` - JSON handling
- `digest` - Hashing
- `DBI` & `RSQLite` - Database operations
- `ellmer` - Structured LLM outputs
- `ohseer` - OCR processing

## License

MIT License