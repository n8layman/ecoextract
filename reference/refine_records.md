# Ecological Data Refinement Functions

Refine and enhance extracted ecological interaction data Refine
extracted records with additional context

## Usage

``` r
refine_records(
  db_conn = NULL,
  document_id,
  extraction_prompt_file = NULL,
  refinement_prompt_file = NULL,
  refinement_context_file = NULL,
  schema_file = NULL,
  model = "anthropic/claude-sonnet-4-5"
)
```

## Arguments

- db_conn:

  Database connection or path to SQLite database file

- document_id:

  Document ID

- extraction_prompt_file:

  Path to extraction prompt file (provides domain context)

- refinement_prompt_file:

  Path to custom refinement prompt file (optional, uses generic if not
  provided)

- refinement_context_file:

  Path to custom refinement context template file (optional)

- schema_file:

  Path to custom schema JSON file (optional)

- model:

  Provider and model in format "provider/model" (default:
  "anthropic/claude-sonnet-4-5")

## Value

List with refinement results
