# tests/testthat/setup.R
#
# This file runs once before any tests are executed.
# Use it for global test configuration, not for package loading.

# Package is automatically loaded by testthat during testing
# devtools::load_all() only works in interactive sessions, not during R CMD check
library(devtools)

# Global test configuration
options(ecoextract.verbose = FALSE)

# Load environment variables from .env files using base R
# Load from package root (one level up from tests/testthat)
root_dir <- file.path("..", "..")
env_files <- list.files(root_dir, pattern = "^\\.env.*", all.files = TRUE, full.names = TRUE)

if (length(env_files) > 0) {
  for (env_file in env_files) {
    if (file.exists(env_file)) {
      message("Loading environment from: ", env_file)
      try(readRenviron(env_file), silent = TRUE)
    }
  }
} else {
  message("No .env files found in package root")
}
