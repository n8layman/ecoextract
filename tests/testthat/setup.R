# tests/testthat/setup.R
#
# This file runs once before any tests are executed.
# Use it for global test configuration, not for package loading.

# Package is automatically loaded by testthat during testing
# devtools::load_all() only works in interactive sessions, not during R CMD check
library(devtools)

# Global test configuration
options(ecoextract.verbose = FALSE)

# Load environment variables from .env using {dotenv} + {here}
if (requireNamespace("dotenv", quietly = TRUE) && requireNamespace("here", quietly = TRUE)) {
  env_path <- here::here(".env")

  if (file.exists(env_path)) {
    message("Loading environment from: ", env_path)
    dotenv::load_dot_env(file = env_path)
  } else {
    message("No .env file found at: ", env_path)
  }
} else {
  message("Packages 'dotenv' or 'here' not available; skipping .env load")
}
