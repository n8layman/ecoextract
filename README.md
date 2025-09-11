# EcoExtract

Structured ecological data extraction and refinement from scientific literature.

## Installation

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

EcoExtract requires API keys for Anthropic (Claude) and Mistral (OCR processing).

### Automatic Setup

```r
# Interactive setup - will prompt for API keys
ecoextract::setup_env_file()

# Check status
ecoextract::print_api_status()
```

### Manual Setup

1. Create a `.env` file in your project directory:

```bash
# .env
ANTHROPIC_API_KEY=your_anthropic_api_key_here
MISTRAL_API_KEY=your_mistral_api_key_here
```

2. Load the environment variables:

```r
# Load environment variables
ecoextract::load_env_file()

# Or set them directly in R
Sys.setenv(ANTHROPIC_API_KEY = "your_key_here")
Sys.setenv(MISTRAL_API_KEY = "your_key_here")
```

### Get API Keys

- **Anthropic API**: https://console.anthropic.com/
- **Mistral API**: https://console.mistral.ai/

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
extraction_result <- extract_interactions(
  markdown_text = your_ocr_text,
  ocr_audit = quality_analysis
)

# Refine the extracted interactions  
refinement_result <- refine_interactions(
  interactions = extraction_result$interactions,
  markdown_text = your_ocr_text,
  ocr_audit = quality_analysis
)
```

### Work with Custom Prompts

```r
# View available prompts
list_prompts()

# View a specific prompt
view_prompt("extraction_prompt")

# Copy prompts locally for customization
copy_prompts_to_local("my_prompts/")

# Load custom prompts
custom_prompts <- load_custom_prompts("my_prompts/")
```

## Database Operations

```r
# Initialize a new database
init_ecoextract_database("my_results.sqlite")

# Get database statistics
stats <- get_db_stats("my_results.sqlite")
print(stats)
```

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

## Configuration

```r
# Check current configuration
print_config()

# Check API key status
print_api_status()

# Get detailed configuration
config <- get_config()
```

## Package Functions

### Core Processing
- `process_ecological_documents()` - Main CLI function for batch processing
- `extract_interactions()` - Extract interactions from text
- `refine_interactions()` - Refine and enhance extracted data
- `enrich_publication_metadata()` - Enrich publication metadata via CrossRef

### Database Operations  
- `init_ecoextract_database()` - Initialize database with proper schema
- `save_document_to_db()` - Save document metadata
- `save_interactions_to_db()` - Save interaction data
- `get_db_stats()` - Get database statistics

### Schema & Validation
- `validate_interactions_schema()` - Validate data against schema
- `get_database_schema()` - Get schema information
- `filter_to_schema_columns()` - Filter data to known columns

### Prompts & Configuration
- `get_extraction_prompt()` - Get extraction prompt from package
- `get_refinement_prompt()` - Get refinement prompt from package  
- `list_prompts()` - List available prompts
- `view_prompt()` - View a specific prompt
- `copy_prompts_to_local()` - Copy prompts for customization
- `setup_env_file()` - Set up API keys
- `load_env_file()` - Load environment variables
- `print_api_status()` - Check API configuration

### Utilities
- `generate_occurrence_id()` - Generate unique occurrence IDs
- `add_occurrence_ids()` - Add IDs to interaction data
- `ecoextract_info()` - Package information

## Testing

```r
# Run the test script
source("test_ecoextract.R")
```

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
- `rcrossref` - Publication metadata enrichment

## License

MIT License