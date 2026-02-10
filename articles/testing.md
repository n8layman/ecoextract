# Testing Philosophy

## Core Principle

**Test functionality, not domain content.**

EcoExtract tests verify that the package’s core operations work
correctly regardless of the specific schema, prompts, or ecological
domain. Tests never check whether the LLM produces “correct” extractions
– they verify that the pipeline machinery functions properly.

This means:

- **No schema-specific assertions** – tests don’t look for field names
  like `bat_species` or `pathogen_name`
- **No prompt effectiveness testing** – tests don’t check whether
  extraction finds specific data in text
- **No LLM quality evaluation** – tests verify API calls return valid
  structure, not accurate content
- **Schema-agnostic fixtures** – test schemas deliberately differ from
  the package defaults

## Test Categories

### Local Tests (no API keys required)

These tests run entirely offline and execute in under a second. They are
always run by
[`devtools::test()`](https://devtools.r-lib.org/reference/test.html) and
[`devtools::check()`](https://devtools.r-lib.org/reference/check.html).

**`test-database.R`** – Database operations:

- Database initialization creates required tables (documents, records,
  record_edits)
- Database schema matches JSON schema definition
- Records can be saved and retrieved
- Array fields stored as single-level JSON arrays

**`test-review.R`** – Human review and accuracy:

- [`save_document()`](https://n8layman.github.io/ecoextract/reference/save_document.md)
  updates reviewed_at timestamp
- Modified records marked as human_edited
- Deleted records marked as deleted_by_user
- Edit tracking populates record_edits table
- [`calculate_accuracy()`](https://n8layman.github.io/ecoextract/reference/calculate_accuracy.md)
  returns correct structure and metrics

**`test-utils.R`** – Utility functions:

- Record ID generation and formatting
- Special character handling in IDs
- Token estimation for various inputs

**`test-deduplication.R`** – Deduplication logic:

- Text canonicalization (Unicode normalization, case folding, whitespace
  trimming)
- Cosine similarity and Jaccard similarity calculation
- Jaccard-based deduplication (exact duplicates, typos, partial matches)
- Schema validation (x-unique-fields required and valid)

**`test-bibtex.R`** – BibTeX export:

- Document metadata exports as valid BibTeX entries
- Citation extraction from bibliography field
- Handles incomplete metadata gracefully

### Integration Tests (require API keys)

These tests make real API calls and validate the end-to-end pipeline.
They are **automatically skipped** when the required API keys are not
set, so contributors without keys can still run the local test suite.

**Required API keys:**

| Key                 | Service                                            | Used For                                                 |
|---------------------|----------------------------------------------------|----------------------------------------------------------|
| `ANTHROPIC_API_KEY` | [Anthropic Claude](https://console.anthropic.com/) | Data extraction, metadata, refinement, LLM deduplication |
| `MISTRAL_API_KEY`   | [Tensorlake](https://www.tensorlake.ai/)           | OCR processing (via ohseer)                              |
| `OPENAI_API_KEY`    | [OpenAI](https://platform.openai.com/)             | Embedding-based deduplication                            |

**`test-integration.R`** – All API-requiring tests in one file:

- Full pipeline: PDF to database (OCR, metadata, extraction, refinement)
- API failures captured in status columns, not thrown as errors
- Schema-agnostic pipeline with a host-pathogen schema (proves no
  hard-coded assumptions)
- Embedding-based deduplication (exact duplicates, near-duplicates,
  missing fields)
- Field-by-field deduplication (partial matches, populated field
  comparison)
- LLM-based semantic deduplication (common names vs scientific names)

## Running Tests

``` r
# Run all tests (integration tests auto-skip without keys)
devtools::test()

# Run a specific test file
testthat::test_file("tests/testthat/test-database.R")

# Full package check (includes tests, documentation, examples)
devtools::check()
```

To include integration tests, set up API keys in a `.env` file (see the
[Complete
Guide](https://n8layman.github.io/ecoextract/articles/ecoextract-workflow.html#api-key-setup)
for details). The `.env` file is automatically loaded when R starts in
the project directory.

## Design Patterns

**Cleanup with withr.** All test resources (temp databases, files,
environment variables) are cleaned up automatically using `withr`,
ensuring no side effects between tests.

**Focused assertions.** Each `test_that()` block tests one specific
behavior rather than bundling multiple concerns.

**Edge case coverage.** Tests cover typical usage, edge cases (empty
inputs, NULL values), error conditions, and type validation.

**Schema-agnostic design.** Test fixtures use schemas that deliberately
differ from the package defaults, proving no hard-coded domain
assumptions exist in the pipeline.

**API key gating.** Integration tests use `skip_if()` guards so the full
local test suite passes without any API keys configured.
