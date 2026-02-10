# Testing Guide for EcoExtract

## Testing Philosophy

**Core Principle: Test functionality, not domain content.**

Tests verify that the package's core operations work correctly, regardless of the specific schema, prompts, or ecological domain being used.

### What We Test

**Database Operations**
- Database initialization creates required tables
- Database schema matches JSON schema definition
- Records can be saved and retrieved
- Constraints and indexes work correctly

**Schema Validation**
- Validation correctly identifies valid vs invalid data structures
- Column filtering works
- Type checks work

**ID Generation**
- Record IDs are generated in the correct format
- IDs handle special characters properly
- IDs are unique

**API Integration Structure**
- API calls (extract, refine, audit) return the expected structure
- Required fields are present in responses
- Error cases return appropriate structures

### What We Don't Test

**Schema-Specific Content**
- Don't test for specific field names like `bat_species_scientific_name`
- Do test that records match the schema structure dynamically

**Prompt Effectiveness**
- Don't test whether extraction finds specific data in text
- Do test that extraction returns a valid dataframe

**Domain Knowledge**
- Don't test whether specific domain values are valid
- Do test that fields accept appropriate value types

**LLM Output Quality**
- Don't test whether the LLM correctly identifies content
- Do test that API calls complete and return valid JSON

## Test Structure

### Local Tests (no API keys required)

These run entirely offline and execute in under a second.

- **test-database.R** - Database initialization, schema validation, save/retrieve records, array field handling
- **test-review.R** - Human review workflow (`save_document`), edit tracking, accuracy metrics
- **test-utils.R** - Record ID generation, token estimation
- **test-deduplication.R** - Canonicalization, similarity functions, Jaccard-based deduplication
- **test-bibtex.R** - BibTeX export and citation extraction

### Integration Tests (require API keys)

- **test-integration.R** - Full pipeline (OCR, extraction, refinement), schema-agnostic pipeline, embedding/field-by-field/LLM deduplication
- Requires `ANTHROPIC_API_KEY`, `MISTRAL_API_KEY`, and optionally `OPENAI_API_KEY`
- Verify response structure only, not content accuracy
- Automatically skipped when API keys are not set

## Best Practices

### 1. Automatic Cleanup with withr

Use `withr` package for automatic cleanup instead of `on.exit()`:

```r
# Preferred: Using withr
test_that("database operations work", {
  db_path <- local_test_db()  # Automatically cleaned up
  # test code
})

# Acceptable but not preferred: Using on.exit
test_that("database operations work", {
  db_path <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db_path))
  # test code
})
```

Benefits of withr:
- Cleanup happens in reverse order of setup
- More robust error handling
- Cleaner test code
- Follows modern R testing practices

### 2. Clear Test Descriptions

Each `test_that()` call has a clear, specific description:

```r
# Good
test_that("save_document_to_db inserts new document", { })

# Bad
test_that("database test", { })
```

### 3. Multiple Small Tests

Prefer multiple focused tests over fewer large tests:

```r
# Good - Separate tests for different behaviors
test_that("function handles valid input", { })
test_that("function handles NULL input", { })
test_that("function handles empty input", { })

# Bad - One test covering everything
test_that("function works", {
  # Tests valid, NULL, and empty all in one
})
```

### 4. Testing Edge Cases

Each function is tested for:
- Typical usage - Expected inputs and outputs
- Edge cases - Empty inputs, NULL values, boundary conditions
- Error conditions - Invalid inputs, missing data
- Type validation - Correct data types returned

## Running Tests

### Loading the Package for Development

Before running tests, load the package using `devtools`:

```r
# Install devtools if needed
install.packages("devtools")

# Load all package code (run from package root directory)
devtools::load_all()
```

### Executing Tests

```r
# Test a single file
testthat::test_file("tests/testthat/test-database.R")

# Test entire package
testthat::test_dir("tests/testthat")

# Using devtools (recommended - loads package and runs tests)
devtools::test()

# Check entire package (includes tests plus documentation, examples, etc.)
devtools::check()
```

### Setting Up Integration Tests

Integration tests require API keys:

```r
# Set API keys before running integration tests
Sys.setenv(ANTHROPIC_API_KEY = "your-key")
Sys.setenv(MISTRAL_API_KEY = "your-key")

# Run integration tests
testthat::test_file("tests/testthat/test-integration.R")
```

## Test Files

All test files are in `tests/testthat/` and follow these conventions:

- **test-database.R** - Database initialization, schema validation, save/retrieve records
- **test-review.R** - Human review workflow, edit tracking, accuracy metrics
- **test-utils.R** - Record ID generation, token estimation
- **test-deduplication.R** - Deduplication logic (local, no API calls)
- **test-bibtex.R** - BibTeX export functionality
- **test-integration.R** - All API-requiring tests (full pipeline, schema-agnostic, deduplication methods)

Naming convention: Test files must start with `test-`

## Special Files

### helper.R

Contains reusable test fixtures and helper functions:

- `local_test_db()` - Creates temporary test database with automatic cleanup
- Sample data functions for testing various components

Purpose: Helper files are automatically loaded before test files and should contain test fixtures, custom expectations, and utility functions used across multiple test files.

### setup.R

Runs once before any tests execute. Contains:

- Package loading logic (for manual testing outside of `devtools` workflow)
- Global test configuration
- Options setting

Purpose: Setup files are for global test configuration, not for helper functions.

## Common Patterns

### Creating Test Databases

```r
test_that("my database test", {
  db_path <- local_test_db()  # Auto-cleanup

  # Run tests

  # No manual cleanup needed
})
```

### Testing Database Content

```r
test_that("data is saved correctly", {
  db_path <- local_test_db()

  # Save data
  save_records_to_db(db_path, doc_id, records, metadata)

  # Verify with direct DB query
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  result <- DBI::dbGetQuery(con, "SELECT * FROM records")
  expect_equal(nrow(result), expected_count)
})
```

### Using Sample Data

```r
test_that("schema validation works", {
  data <- sample_records()  # Use helper function

  result <- validate_records_schema(data)

  expect_true(result$valid)
})
```

## Adding New Tests

When adding a test, ask:

1. **Is this testing functionality or content?**
   - Functionality (good): "Can we save records?"
   - Content (bad): "Does it find this specific species?"

2. **Will this test break if someone changes the schema?**
   - If yes, make it schema-agnostic

3. **Am I testing the LLM's accuracy?**
   - If yes, this is outside the scope of ecoextract tests

4. **Is this core to the package's mission?**
   - Core: OCR, extraction, refinement, database
   - Not core: Convenience functions, info printers

## Dependencies

Test suite requires:

- `testthat` (>= 3.0.0)
- `withr` - For automatic cleanup
- `DBI` & `RSQLite` - For database testing
- `digest` - For hash generation in tests

## Resources

- [testthat documentation](https://testthat.r-lib.org/)
- [R Packages - Testing basics](https://r-pkgs.org/testing-basics.html)
- [testthat special files](https://testthat.r-lib.org/articles/special-files.html)
- [Test fixtures guide](https://testthat.r-lib.org/articles/test-fixtures.html)
