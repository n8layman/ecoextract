#' Configuration and API Key Management
#' 
#' Handle API keys, environment variables, and package configuration

#' Check if required API keys are available
#' @return List with API key status
#' @export
check_api_keys <- function() {
  keys <- list(
    anthropic = get_anthropic_key(),
    mistral = get_mistral_key()
  )
  
  status <- list(
    anthropic_available = !is.null(keys$anthropic) && keys$anthropic != "",
    mistral_available = !is.null(keys$mistral) && keys$mistral != "",
    all_available = FALSE
  )
  
  status$all_available <- status$anthropic_available && status$mistral_available
  
  return(status)
}

#' Get Anthropic API key from environment
#' @return API key string or NULL if not found
get_anthropic_key <- function() {
  key <- Sys.getenv("ANTHROPIC_API_KEY")
  if (key == "") {
    # Try alternative environment variable names
    key <- Sys.getenv("CLAUDE_API_KEY")
  }
  if (key == "") return(NULL)
  return(key)
}

#' Get Mistral API key from environment
#' @return API key string or NULL if not found
get_mistral_key <- function() {
  key <- Sys.getenv("MISTRAL_API_KEY")
  if (key == "") return(NULL)
  return(key)
}

#' Set up environment file with API keys
#' @param env_file Path to .env file (default: .env in working directory)
#' @param anthropic_key Anthropic API key (optional, will prompt if not provided)
#' @param mistral_key Mistral API key (optional, will prompt if not provided)
#' @param interactive Whether to prompt user for keys interactively
#' @return TRUE if successful
#' @export
setup_env_file <- function(env_file = ".env", anthropic_key = NULL, mistral_key = NULL, interactive = TRUE) {
  
  if (interactive && (is.null(anthropic_key) || is.null(mistral_key))) {
    cat("Setting up API keys for ecoextract package...\n\n")
    
    if (is.null(anthropic_key)) {
      cat("Please enter your Anthropic API key (for Claude models):\n")
      cat("Get your key from: https://console.anthropic.com/\n")
      anthropic_key <- readline(prompt = "Anthropic API key: ")
    }
    
    if (is.null(mistral_key)) {
      cat("\nPlease enter your Mistral API key (for OCR processing):\n")
      cat("Get your key from: https://console.mistral.ai/\n")
      mistral_key <- readline(prompt = "Mistral API key: ")
    }
  }
  
  if (is.null(anthropic_key) || is.null(mistral_key)) {
    stop("API keys are required for ecoextract to function properly")
  }
  
  # Create .env file content
  env_content <- paste0(
    "# EcoExtract API Configuration\n",
    "# Generated on ", Sys.Date(), "\n\n",
    "# Anthropic API key for Claude models (extraction and refinement)\n",
    "ANTHROPIC_API_KEY=", anthropic_key, "\n\n",
    "# Mistral API key for OCR processing\n",
    "MISTRAL_API_KEY=", mistral_key, "\n\n",
    "# Optional: Set default database path\n",
    "# ECOEXTRACT_DB_PATH=my_custom_results.sqlite\n"
  )
  
  # Write .env file
  writeLines(env_content, env_file)
  
  # Add .env to .gitignore if it exists
  gitignore_path <- ".gitignore"
  if (file.exists(gitignore_path)) {
    gitignore_content <- readLines(gitignore_path)
    if (!any(grepl("^\\.env$", gitignore_content))) {
      writeLines(c(gitignore_content, "", "# Environment variables", ".env"), gitignore_path)
      cat("Added .env to .gitignore\n")
    }
  } else {
    writeLines(c("# Environment variables", ".env"), gitignore_path)
    cat("Created .gitignore with .env entry\n")
  }
  
  cat("✅ Environment file created:", env_file, "\n")
  cat("Please restart R or run Sys.setenv() to load the new API keys.\n")
  
  return(TRUE)
}

#' Load environment variables from .env file
#' @param env_file Path to .env file
#' @return TRUE if file was loaded successfully
#' @export
load_env_file <- function(env_file = ".env") {
  if (!file.exists(env_file)) {
    cat("No .env file found at:", env_file, "\n")
    cat("Run setup_env_file() to create one.\n")
    return(FALSE)
  }
  
  tryCatch({
    env_lines <- readLines(env_file)
    
    # Parse environment variables
    for (line in env_lines) {
      # Skip comments and empty lines
      if (grepl("^\\s*#", line) || grepl("^\\s*$", line)) next
      
      # Parse KEY=VALUE format
      if (grepl("=", line)) {
        parts <- strsplit(line, "=", fixed = TRUE)[[1]]
        if (length(parts) >= 2) {
          key <- trimws(parts[1])
          value <- paste(parts[-1], collapse = "=")  # Handle values with = signs
          value <- trimws(value)
          
          # Remove quotes if present
          if (grepl('^".*"$', value) || grepl("^'.*'$", value)) {
            value <- substr(value, 2, nchar(value) - 1)
          }
          
          Sys.setenv(setNames(value, key))
        }
      }
    }
    
    cat("✅ Loaded environment variables from:", env_file, "\n")
    return(TRUE)
    
  }, error = function(e) {
    cat("Error loading .env file:", e$message, "\n")
    return(FALSE)
  })
}

#' Print API key configuration status
#' @export
print_api_status <- function() {
  status <- check_api_keys()
  
  cat("=== EcoExtract API Configuration Status ===\n\n")
  
  cat("Anthropic API (Claude):", if (status$anthropic_available) "✅ Available" else "❌ Not found", "\n")
  cat("Mistral API (OCR):     ", if (status$mistral_available) "✅ Available" else "❌ Not found", "\n")
  
  if (!status$all_available) {
    cat("\n⚠️  Missing API keys detected!\n\n")
    cat("To set up API keys:\n")
    cat("1. Run: ecoextract::setup_env_file()\n")
    cat("2. Or manually create .env file with:\n")
    cat("   ANTHROPIC_API_KEY=your_anthropic_key\n")
    cat("   MISTRAL_API_KEY=your_mistral_key\n")
    cat("3. Restart R or run: ecoextract::load_env_file()\n\n")
    cat("Get API keys from:\n")
    cat("- Anthropic: https://console.anthropic.com/\n")
    cat("- Mistral: https://console.mistral.ai/\n")
  } else {
    cat("\n✅ All API keys configured correctly!\n")
  }
}

#' Get package configuration
#' @return List with current configuration
#' @export
get_config <- function() {
  status <- check_api_keys()
  
  config <- list(
    api_keys = status,
    default_db_path = Sys.getenv("ECOEXTRACT_DB_PATH", "ecoextract_results.sqlite"),
    package_version = utils::packageVersion("ecoextract"),
    prompts_available = length(list_prompts()) > 0
  )
  
  return(config)
}

#' Print complete package configuration
#' @export
print_config <- function() {
  config <- get_config()
  
  cat("=== EcoExtract Package Configuration ===\n\n")
  cat("Package Version:", as.character(config$package_version), "\n")
  cat("Default Database:", config$default_db_path, "\n")
  cat("Available Prompts:", length(list_prompts()), "\n")
  
  print_api_status()
}