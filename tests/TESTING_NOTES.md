# Testing Notes for EcoExtract

This document explains the testing approach and best practices followed in this package.

## Test Structure

We follow [testthat best practices](https://testthat.r-lib.org/) and the [R Packages book](https://r-pkgs.org/testing-basics.html) recommendations.

### Test Files

All test files are in `tests/testthat/` and follow these conventions:

- **test-database.R** - Tests for database operations (`R/database.R`)
- **test-schema.R** - Tests for schema validation (`R/schema.R`)
- **test-utils.R** - Tests for utility functions (`R/utils.R`)

**Naming Convention**: Test files must start with `test-` and ideally have a one-to-one correspondence with source files in `R/`.

### Special Files

#### helper.R

Contains reusable test fixtures and helper functions:

- `local_test_db()` - Creates temporary test database with automatic cleanup
- `sample_interactions()` - Sample interaction data for testing
- `minimal_interactions()` - Minimal valid interaction data
- `sample_publication_metadata()` - Sample publication metadata
- `sample_ocr_content()` - Mock OCR markdown content
- `sample_ocr_audit()` - Mock OCR audit JSON

**Purpose**: Helper files are automatically loaded before test files and should contain:

- Test fixtures
- Custom expectations
- Utility functions used across multiple test files

#### setup.R

Runs once before any tests execute. Contains:

- Package loading logic (for manual testing outside of `devtools` workflow)
- Global test configuration
- Options setting

**Purpose**: Setup files are for global test configuration, not for helper functions.

## Testing Best Practices Used

### 1. Automatic Cleanup with withr

We use `withr` package for automatic cleanup instead of `on.exit()`:

```r
# Good: Using withr
test_that("database operations work", {
  db_path <- local_test_db()  # Automatically cleaned up
  # ... test code ...
})

# Acceptable but not preferred: Using on.exit
test_that("database operations work", {
  db_path <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db_path))
  # ... test code ...
})
```

**Benefits of withr**:

- Cleanup happens in reverse order of setup
- More robust error handling
- Cleaner test code
- Follows modern R testing practices

### 2. Clear Test Descriptions

Each `test_that()` call has a clear, specific description:

```r
# Good
test_that("save_document_to_db inserts new document", { ... })

# Bad
test_that("database test", { ... })
```

### 3. Multiple Small Tests

We prefer multiple focused tests over fewer large tests:

```r
# Good - Separate tests for different behaviors
test_that("function handles valid input", { ... })
test_that("function handles NULL input", { ... })
test_that("function handles empty input", { ... })

# Bad - One test covering everything
test_that("function works", {
  # Tests valid, NULL, and empty all in one
})
```

### 4. Testing Edge Cases

Each function is tested for:

- **Typical usage** - Expected inputs and outputs
- **Edge cases** - Empty inputs, NULL values, boundary conditions
- **Error conditions** - Invalid inputs, missing data
- **Type validation** - Correct data types returned

## Running Tests

### Loading the Package for Development

Before running tests, you need to load the package. The recommended approach uses `devtools`:

```r
# Install devtools if needed
install.packages("devtools")

# Load all package code (run from package root directory)
devtools::load_all()

# This makes all package functions available for interactive testing
# and is equivalent to installing the package, but faster for development
```

Alternative approaches:

```r
# Install the package from local source
devtools::install()

# Or use the standard R approach
install.packages(".", repos = NULL, type = "source")
```

### Executing Tests

```r
# Test a single file
testthat::test_file("tests/testthat/test-schema.R")

# Test entire package
testthat::test_dir("tests/testthat")

# Using devtools (recommended - loads package and runs tests)
devtools::test()

# Check entire package (includes tests plus documentation, examples, etc.)
devtools::check()
```

### During R CMD check

Tests run automatically during `R CMD check` and package installation.

## Test Coverage

Current test coverage: **123 tests, 100% passing**

- **Schema validation**: 41 tests
- **Database operations**: 39 tests
- **Utilities**: 43 tests

### Detailed Test Inventory

#### test-schema.R (41 tests)

**validate_interactions_schema() - 6 tests**

- accepts valid data
- handles empty dataframe
- detects missing required columns in strict mode
- warns about unexpected columns
- warns about type mismatches
- detects empty required fields

**get_schema_columns() - 1 test**

- returns expected column names

**get_schema_types() - 1 test**

- returns correct SQL types

**get_required_columns() - 1 test**

- returns required fields

**filter_to_schema_columns() - 2 tests**

- removes unknown columns
- preserves all schema columns present

**add_missing_schema_columns() - 2 tests**

- adds missing columns with correct types
- doesn't overwrite existing columns

**validate_and_prepare_for_db() - 1 test**

- filters and adds columns

**get_database_schema() - 1 test**

- returns comprehensive schema info

#### test-database.R (39 tests)

**init_ecoextract_database() - 3 tests**

- creates database with required tables
- creates proper indexes
- creates directory if needed

**save_document_to_db() - 2 tests**

- inserts new document
- returns existing ID for duplicate hash

**save_interactions_to_db() - 3 tests**

- inserts interactions
- handles empty dataframe
- serializes JSON arrays

**get_db_stats() - 2 tests**

- returns correct counts
- handles missing database

**get_document_content() - 2 tests**

- retrieves OCR content
- returns NA when not found

**get_ocr_audit() - 1 test**

- retrieves audit data

**get_existing_records() - 2 tests**

- retrieves interactions
- returns NA when none found

#### test-utils.R (43 tests)

**generate_record_id() - 4 tests**

- creates proper format
- handles special characters in author name
- handles empty author name
- creates unique sequential IDs

**add_record_ids() - 3 tests**

- adds IDs to all rows
- creates sequential IDs
- handles empty dataframe

**estimate_tokens() - 6 tests**

- handles NULL input
- handles empty string
- handles NA input
- estimates character input
- converts non-character to JSON
- handles conversion failures gracefully

**log_message() - 2 tests**

- outputs formatted message
- handles different log levels

**ecoextract_info() - 1 test**

- prints package information

**process_single_document() - 1 test**

- handles errors gracefully

**build_existing_records_context() - 5 tests**

- handles empty records
- handles zero-row dataframe
- formats records properly
- handles missing field names
- controls record_id visibility

### Areas Needing More Tests

1. **Extraction functions** - Requires mocking `ellmer` LLM calls
2. **Refinement functions** - Requires mocking `ellmer` LLM calls
3. **Config functions** - API key management and environment setup
4. **Enrichment functions** - Requires mocking CrossRef API calls

## Dependencies

Test suite requires:

- `testthat` (>= 3.0.0)
- `withr` - For automatic cleanup
- `DBI` & `RSQLite` - For database testing
- `digest` - For hash generation in tests

## Common Patterns

### Creating Test Databases

```r
test_that("my database test", {
  db_path <- local_test_db()  # Auto-cleanup

  # Run tests
  # ...

  # No manual cleanup needed!
})
```

### Testing Database Content

```r
test_that("data is saved correctly", {
  db_path <- local_test_db()

  # Save data
  save_interactions_to_db(db_path, doc_id, interactions, metadata)

  # Verify with direct DB query
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  result <- DBI::dbGetQuery(con, "SELECT * FROM interactions")
  expect_equal(nrow(result), expected_count)
})
```

### Using Sample Data

```r
test_that("schema validation works", {
  data <- sample_interactions()  # Use helper function

  result <- validate_interactions_schema(data)

  expect_true(result$valid)
})
```

## Future Improvements

1. **Add snapshot tests** for LLM outputs (when available)
2. **Add integration tests** with real API calls (skipped in CI)
3. **Increase coverage** for extraction/refinement pipelines
4. **Add performance benchmarks** for large document processing

## Resources

- [testthat documentation](https://testthat.r-lib.org/)
- [R Packages - Testing basics](https://r-pkgs.org/testing-basics.html)
- [testthat special files](https://testthat.r-lib.org/articles/special-files.html)
- [Test fixtures guide](https://testthat.r-lib.org/articles/test-fixtures.html)
