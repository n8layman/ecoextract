# Contributing to EcoExtract

Thank you for your interest in contributing to EcoExtract!

## How to Contribute

All contributions must be made via pull request (PR). Direct commits to
the main branch are not accepted.

### Submission Process

1.  Fork the repository
2.  Create a feature branch from `main`
3.  Make your changes following the code style guidelines below
4.  Write tests for new functionality
5.  Run local tests with
    [`devtools::test()`](https://devtools.r-lib.org/reference/test.html)
6.  Run package checks with
    [`devtools::check()`](https://devtools.r-lib.org/reference/check.html)
7.  **Only create a PR when your work is complete and ready for
    review/merge**

**Important:** Each push to a PR branch triggers integration tests in
CI, which consume API credits. To avoid unnecessary costs:

- Feel free to push commits to your fork or branch as you work
- **Only create the PR when your work is complete and ready for merge**
- Avoid creating draft PRs or WIP PRs for early feedback
- If you need early feedback, open an issue for discussion instead

### Merge Policy

- All PRs are merged using **squash merge** to maintain a clean commit
  history
- Write a clear PR description that summarizes all changes
- Your commits will be squashed into a single commit on merge

## Testing

### Local Testing

Run the test suite locally:

``` r
devtools::test()
devtools::check()
```

### Integration Tests

The repository includes integration tests that verify API interactions
with LLM providers (Anthropic for extraction/refinement, Mistral for
OCR). These tests:

- Run automatically on all pull requests via GitHub Actions
- Verify API structure and response formats, not content accuracy
- Are schema-agnostic and work with any domain/prompts

By default, these integration tests will not run locally because API
keys are stored as secrets in the CI environment. However, you can run
them locally if you have your own API keys:

#### Running Integration Tests Locally

1.  Get API keys from the providers:
    - Anthropic: <https://console.anthropic.com/>
    - Mistral: <https://console.mistral.ai/>
2.  Create a `.env` file in the package root (this file is gitignored):

``` bash
# .env
ANTHROPIC_API_KEY=your_anthropic_api_key_here
MISTRAL_API_KEY=your_mistral_api_key_here
```

3.  Load environment variables before running tests:

``` r
# Run all tests including integration tests (loads .env automatically)
library(ecoextract)
devtools::test()
```

**Note:** Never commit API keys to the repository. The `.env` file is
gitignored to prevent accidental commits.

#### CI Integration Tests

When you submit a PR, integration tests will run automatically in CI.
These tests consume API credits, so:

- Only create PRs when your work is complete and ready for merge
- Each push to a PR branch triggers the full integration test suite
- Run tests locally first to catch issues before submitting

If CI integration tests fail, the maintainers will work with you to
resolve any issues.

## Code Style

- Use native pipe `|>` instead of magrittr pipe `%>%`
- Follow the [tidyverse style guide](https://style.tidyverse.org/)
- Use roxygen2 documentation format for all exported functions
- Prefer explicit over implicit code

## Testing Philosophy

- All new functions must have tests
- Use testthat 3rd edition
- Use `withr` for cleanup, not
  [`on.exit()`](https://rdrr.io/r/base/on.exit.html)
- Tests must be schema-agnostic (work with any domain/prompts)
- See `tests/TESTING.md` for detailed testing patterns

## Documentation

- Document all exported functions with roxygen2
- Include examples in function documentation
- Use markdown for documentation files
- Keep README.md up to date with new features

## Code Organization

- **Minimize bloat**: Only include functions that directly serve the
  core mission (OCR, extraction, refinement, database)
- No convenience wrappers or helper functions that users can easily do
  themselves
- **No legacy code**: Delete deprecated code immediately. Don’t keep
  `.old` files or commented-out code blocks

## Questions?

If you have questions about contributing, please open an issue for
discussion before starting work on large features.
