# Testing Philosophy for EcoExtract

## Core Principle

**Test functionality, not domain content.**

Tests should verify that the package's core operations work correctly, regardless of the specific schema, prompts, or ecological domain being used.

## What We Test

### 1. Database Operations
- Does database initialization create required tables?
- Does the database schema match the JSON schema definition?
- Can we save and retrieve records?
- Do constraints and indexes work?

### 2. Schema Validation
- Does validation correctly identify valid vs invalid data structures?
- Does column filtering work?
- Do type checks work?

### 3. ID Generation
- Are occurrence IDs generated in the correct format?
- Do IDs handle special characters properly?
- Are IDs unique?

### 4. API Integration Structure
- Do API calls (extract, refine, audit) return the expected structure?
- Are required fields present in responses?
- Do error cases return appropriate structures?

## What We DON'T Test

### 1. Schema-Specific Content
❌ Don't test for specific field names like `bat_species_scientific_name`
✅ Do test that records match the schema structure dynamically

### 2. Prompt Effectiveness
❌ Don't test whether extraction finds "Myotis lucifugus" in text
✅ Do test that extraction returns a valid dataframe

**Why?** Prompt effectiveness is tested by the `ecovalidate` package, which scores accuracy against ground truth data.

### 3. Domain Knowledge
❌ Don't test whether "Little Brown Bat" is a valid common name
✅ Do test that common_name fields accept string values

### 4. LLM Output Quality
❌ Don't test whether Claude correctly identifies species
✅ Do test that the API call completes and returns valid JSON

## Test Structure

### Unit Tests (`test-core.R`)
- Test individual functions in isolation
- Use minimal, generic test data
- Fast execution (<1 second total)
- No API calls

### Integration Tests (`test-integration.R`)
- Test API calls (requires API keys)
- Verify response structure only, not content
- Can be slow (may take 10-30 seconds)
- Skipped when API keys not available

## Test Data Philosophy

All test fixtures should be **schema-agnostic**:

```r
# ✅ Good: Dynamically generates test data from schema
sample_records <- function() {
  columns <- get_db_schema_columns()
  # Generate generic test data for all columns
}

# ❌ Bad: Hardcoded to bat ecology domain
sample_interactions <- function() {
  data.frame(
    bat_species = "Myotis lucifugus",
    ...
  )
}
```

## Integration with ecovalidate

The `ecovalidate` package handles:
- Accuracy scoring against ground truth
- Precision/recall metrics
- F1 scores
- Prompt effectiveness evaluation

This separation allows:
- `ecoextract` tests to run quickly without needing labeled data
- `ecovalidate` tests to thoroughly evaluate extraction quality
- Different schemas/prompts to be tested independently

## Test Inventory

### Core Tests (test-core.R) - 10 test cases, ~24 assertions
**No API keys required** - Fast execution (<1 second)

#### Database Core (3 tests)
1. **"database initialization creates required tables"**
   - Verifies `init_ecoextract_database()` creates `documents` and `interactions` tables
   - Tests: Table existence in SQLite database

2. **"database schema matches JSON schema definition"**
   - Ensures database columns match the schema JSON definition
   - Tests: Column names alignment between DB and schema

3. **"save and retrieve records workflow"**
   - Tests full cycle: save document → save records → verify in database
   - Tests: Document ID generation, record persistence, row counts

#### Schema Validation (3 tests)
4. **"validate_interactions_schema accepts valid data"**
   - Checks that valid sample records pass validation
   - Tests: Validation returns `valid=TRUE`, no errors

5. **"validate_interactions_schema reports warnings for unknown columns"**
   - Ensures extra columns are detected but don't fail validation
   - Tests: Unknown columns flagged, validation still passes

6. **"filter_to_schema_columns removes unknown columns"**
   - Tests that unknown columns are properly filtered out
   - Tests: Extra columns removed, schema columns retained

#### ID Generation (3 tests)
7. **"generate_occurrence_id creates correct format"**
   - Verifies occurrence ID format: `AuthorYear-oN`
   - Tests: String format matches pattern

8. **"generate_occurrence_id handles special characters"**
   - Tests that special chars like apostrophes are stripped
   - Tests: Clean IDs without special characters

9. **"add_occurrence_ids adds IDs to all rows"**
   - Ensures all records get unique occurrence IDs
   - Tests: All rows have non-NA IDs

#### Utilities (1 test)
10. **"estimate_tokens handles various inputs"**
    - Tests token estimation for NULL, empty, NA, and regular text
    - Tests: Returns 0 for empty inputs, positive for text

### Integration Tests (test-integration.R) - 5 test cases, ~27 assertions
**Requires API keys** - Slower execution (10-60 seconds depending on API speed)

#### Step 1: OCR (1 test)
11. **"step 1: OCR with Mistral"**
    - **Requires**: `MISTRAL_API_KEY`
    - Calls `ohseer::mistral_ocr()` on test PDF
    - Tests: Response structure, pages array, markdown content
    - Purpose: Verify OCR API integration works

#### Step 2: OCR Audit (1 test)
12. **"step 2: OCR audit and save to database"**
    - **Requires**: `ANTHROPIC_API_KEY`
    - Calls `perform_ocr_audit()` with sample OCR content
    - Saves document to database
    - Tests: Audited markdown returned, document saved with correct ID
    - Purpose: Verify OCR audit API and database save

#### Step 3: Extraction (1 test)
13. **"step 3: extraction and save to database"**
    - **Requires**: `ANTHROPIC_API_KEY`
    - Calls `extract_records()` standalone (without DB connection)
    - Manually saves extracted records to database
    - Tests: Status/records_extracted in response, records saved to DB
    - Purpose: Verify **standalone extraction** use case

#### Step 4: Refinement (1 test)
14. **"step 4: refinement and save to database"**
    - **Requires**: `ANTHROPIC_API_KEY`
    - Pre-populates database with sample records
    - Calls `refine_records()` which reads from DB and saves back
    - Tests: Status is "completed", refined records in database
    - Purpose: Verify **atomic refinement** (DB → process → DB)

#### Step 5: Full Pipeline (1 test)
15. **"step 5: full pipeline from PDF to database"**
    - **Requires**: `MISTRAL_API_KEY` + `ANTHROPIC_API_KEY`
    - Calls `process_documents()` on real PDF
    - Tests **complete 4-step workflow**: OCR → Audit → Extract → Refine
    - Tests: All statuses "completed" or "skipped", records extracted > 0, data in database
    - Purpose: **Main integration test** - verifies end-to-end pipeline

### Total: 15 test cases, 51 assertions

## Running Tests

```r
# Run all tests (51 assertions)
devtools::test()

# Run only core tests (no API, ~24 assertions)
testthat::test_file("tests/testthat/test-core.R")

# Run integration tests (requires API keys, ~27 assertions)
Sys.setenv(ANTHROPIC_API_KEY = "your-key")
Sys.setenv(MISTRAL_API_KEY = "your-key")
testthat::test_file("tests/testthat/test-integration.R")
```

## Adding New Tests

When adding a test, ask:
1. **Is this testing functionality or content?**
   - Functionality ✅ (e.g., "Can we save records?")
   - Content ❌ (e.g., "Does it find this specific species?")

2. **Will this test break if someone changes the schema?**
   - If yes, make it schema-agnostic

3. **Am I testing the LLM's accuracy?**
   - If yes, this belongs in `ecovalidate`, not here

4. **Is this core to the package's mission?**
   - Core: OCR, extraction, refinement, database
   - Not core: Convenience functions, info printers
