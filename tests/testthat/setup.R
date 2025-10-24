# Setup file for testthat
#
# This file runs once before any tests are executed.
# Use it for global test configuration, not for loading the package.
# The package should be loaded via devtools::load_all() or during R CMD check.

# For manual testing (when running tests outside of devtools/R CMD check)
# Try to load the package if not already loaded
if (!isNamespaceLoaded("ecoextract")) {
  # Source all R files from the package
  r_files <- list.files(
    path = "../../R",
    pattern = "\\.R$",
    full.names = TRUE
  )

  for (file in r_files) {
    source(file, local = FALSE)
  }

  # Load required packages
  suppressPackageStartupMessages({
    library(dplyr)
    library(DBI)
    library(RSQLite)
    library(digest)
    library(withr)
  })
}

# Global test configuration
# Suppress verbose output during tests for cleaner test output
options(ecoextract.verbose = FALSE)
