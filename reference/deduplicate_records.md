# Deduplicate records using semantic similarity

Compares new records against existing records using embeddings of
composite keys. Only inserts records that don't match existing records
above the similarity threshold.

## Usage

``` r
deduplicate_records(
  new_records,
  existing_records,
  schema_list,
  min_similarity = 0.9,
  embedding_provider = "mistral",
  similarity_method = "llm",
  model = "anthropic/claude-sonnet-4-5"
)
```

## Arguments

- new_records:

  Dataframe of newly extracted records

- existing_records:

  Dataframe of existing records from database

- schema_list:

  Parsed JSON schema (list) containing required fields

- min_similarity:

  Minimum cosine similarity to consider a duplicate (default: 0.9)

- embedding_provider:

  Provider for embeddings (default: "mistral")

- similarity_method:

  Method for similarity calculation: "embedding", "jaccard", or "llm"
  (default: "llm")

- model:

  LLM model for llm method (default: "anthropic/claude-sonnet-4-5")

## Value

List with deduplicated records and metadata
