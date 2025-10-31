source("renv/activate.R")

# Load environment variables from .env file
if (requireNamespace("dotenv", quietly = TRUE)) {
  env_file <- ".env"
  if (file.exists(env_file)) {
    tryCatch({
      dotenv::load_dot_env(file = env_file)
      message("Loading environment from: ", normalizePath(env_file))
    }, error = function(e) {
      warning("Failed to load .env file: ", e$message)
    })
  }
}
