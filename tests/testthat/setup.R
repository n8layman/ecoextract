# tests/testthat/setup.R
#
# This file runs once before any tests are executed.
# Use it for global test configuration, not for package loading.

# Optional: load the package manually when running tests
if (!isNamespaceLoaded("ecoextract")) {
  message("Loading ecoextract for manual testing...")
  suppressMessages(devtools::load_all("../../"))
}

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
