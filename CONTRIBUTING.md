# Contributing to EcoExtract

Interested in contributing? Reach out by opening an issue first -- we'd like to coordinate before you start work.

## Rules

- All changes via pull request (squash-merged to main)
- Run `devtools::test()` and `devtools::check()` before submitting
- Only create a PR when your work is complete -- each push triggers CI integration tests that consume API credits
- Use native pipe `|>`, tidyverse style, roxygen2 docs
- Tests must be schema-agnostic (see `tests/TESTING.md`)
- Use `withr` for cleanup in tests
