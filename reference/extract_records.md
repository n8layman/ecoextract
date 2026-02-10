# Ecological Data Extraction Functions

Extract structured ecological interaction data from OCR-processed
documents Extract records from markdown text

## Usage

``` r
extract_records(
  document_id = NA,
  db_conn = NA,
  document_content = NA,
  extraction_prompt_file = NULL,
  extraction_context_file = NULL,
  schema_file = NULL,
  model = "anthropic/claude-sonnet-4-5",
  min_similarity = 0.9,
  embedding_provider = "openai",
  similarity_method = "llm",
  ...
)
```

## Arguments

- document_id:

  Optional document ID for context

- db_conn:

  Optional path to interaction database

- document_content:

  OCR-processed markdown content

- extraction_prompt_file:

  Path to custom extraction prompt file (optional)

- extraction_context_file:

  Path to custom extraction context template file (optional)

- schema_file:

  Path to custom schema JSON file (optional)

- model:

  Provider and model in format "provider/model" (default:
  "anthropic/claude-sonnet-4-5")

- min_similarity:

  Minimum similarity for deduplication (default: 0.9)

- embedding_provider:

  Provider for embeddings when using embedding method (default:
  "mistral")

- similarity_method:

  Method for deduplication similarity: "embedding", "jaccard", or "llm"
  (default: "llm")

- ...:

  Additional arguments passed to extraction

## Value

List with extraction results

## Details

Skip logic is handled by the workflow - this function always runs when
called. Uses deduplication to avoid creating duplicate records.
