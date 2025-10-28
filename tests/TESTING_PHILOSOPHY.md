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

## Running Tests

```r
# Run all tests
devtools::test()

# Run only core tests (no API)
testthat::test_file("tests/testthat/test-core.R")

# Run integration tests (requires API keys)
Sys.setenv(ANTHROPIC_API_KEY = "your-key")
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
