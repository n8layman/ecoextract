# Process Single Document Through Complete Pipeline

Process Single Document Through Complete Pipeline

## Usage

``` r
process_single_document(
  pdf_file,
  db_conn,
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
  ...
)
```

## Arguments

- pdf_file:

  Path to PDF file

- db_conn:

  Database connection

- schema_file:

  Optional custom schema

- extraction_prompt_file:

  Optional custom extraction prompt

- refinement_prompt_file:

  Optional custom refinement prompt

- force_reprocess_ocr:

  NULL, TRUE, or integer vector of document_ids to force OCR

- force_reprocess_metadata:

  NULL, TRUE, or integer vector of document_ids to force metadata

- force_reprocess_extraction:

  NULL, TRUE, or integer vector of document_ids to force extraction

- run_extraction:

  If TRUE, run extraction step (default: TRUE)

- run_refinement:

  NULL, TRUE, or integer vector of document_ids to run refinement

- min_similarity:

  Minimum cosine similarity for deduplication (default: 0.9)

- embedding_provider:

  Provider for embeddings (default: "openai")

- similarity_method:

  Method for deduplication similarity: "embedding", "jaccard", or "llm"
  (default: "llm")

- ...:

  Additional arguments passed to underlying functions (e.g.,
  max_wait_seconds for OCR timeout)

## Value

List with processing result
