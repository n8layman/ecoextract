#' Prompt Management Functions
#' 
#' Handle system prompts and templates for ecological data extraction

#' Get extraction prompt from package
#' @return Character string with extraction prompt
#' @export
get_extraction_prompt <- function() {
  prompt_path <- system.file("prompts", "extraction_prompt.md", package = "ecoextract")
  
  if (!file.exists(prompt_path)) {
    stop("Extraction prompt not found in package. Please ensure ecoextract is properly installed.")
  }
  
  readr::read_file(prompt_path)
}

#' Get refinement prompt from package
#' @return Character string with refinement prompt
#' @export
get_refinement_prompt <- function() {
  prompt_path <- system.file("prompts", "refinement_prompt.md", package = "ecoextract")
  
  if (!file.exists(prompt_path)) {
    stop("Refinement prompt not found in package. Please ensure ecoextract is properly installed.")
  }
  
  readr::read_file(prompt_path)
}

#' Get extraction context template from package
#' @return Character string with context template
#' @export
get_extraction_context_template <- function() {
  template_path <- system.file("prompts", "extraction_context.md", package = "ecoextract")
  
  if (!file.exists(template_path)) {
    stop("Extraction context template not found in package. Please ensure ecoextract is properly installed.")
  }
  
  readr::read_file(template_path)
}

#' List all available prompts in package
#' @return Character vector of available prompt files
#' @export
list_prompts <- function() {
  prompts_dir <- system.file("prompts", package = "ecoextract")
  
  if (!dir.exists(prompts_dir)) {
    return(character(0))
  }
  
  list.files(prompts_dir, pattern = "\\.md$")
}

#' View a specific prompt
#' @param prompt_name Name of the prompt file (without .md extension)
#' @return Character string with prompt content
#' @export
view_prompt <- function(prompt_name) {
  if (!grepl("\\.md$", prompt_name)) {
    prompt_name <- paste0(prompt_name, ".md")
  }
  
  prompt_path <- system.file("prompts", prompt_name, package = "ecoextract")
  
  if (!file.exists(prompt_path)) {
    available <- list_prompts()
    stop("Prompt '", prompt_name, "' not found. Available prompts: ", paste(available, collapse = ", "))
  }
  
  content <- readr::read_file(prompt_path)
  cat(content)
  return(invisible(content))
}

#' Get prompt directory path for custom prompts
#' @return Character string with path to prompts directory
#' @export
get_prompts_dir <- function() {
  prompts_dir <- system.file("prompts", package = "ecoextract")
  
  if (!dir.exists(prompts_dir)) {
    stop("Prompts directory not found. Please ensure ecoextract is properly installed.")
  }
  
  return(prompts_dir)
}

#' Copy prompts to local directory for customization
#' @param dest_dir Destination directory for prompts
#' @param overwrite Whether to overwrite existing files
#' @return TRUE if successful
#' @export
copy_prompts_to_local <- function(dest_dir = "prompts", overwrite = FALSE) {
  # Create destination directory
  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE)
  }
  
  # Get source prompts directory
  source_dir <- get_prompts_dir()
  
  # Copy all prompt files
  prompt_files <- list.files(source_dir, pattern = "\\.md$", full.names = TRUE)
  
  copied_files <- character(0)
  
  for (file_path in prompt_files) {
    file_name <- basename(file_path)
    dest_path <- file.path(dest_dir, file_name)
    
    if (!file.exists(dest_path) || overwrite) {
      file.copy(file_path, dest_path, overwrite = overwrite)
      copied_files <- c(copied_files, file_name)
    }
  }
  
  if (length(copied_files) > 0) {
    cat("Copied prompts to", dest_dir, ":\n")
    cat(paste("  -", copied_files), sep = "\n")
    cat("\nYou can now customize these prompts for your specific use case.\n")
  } else {
    cat("No files copied. Use overwrite = TRUE to replace existing files.\n")
  }
  
  return(length(copied_files) > 0)
}

#' Load custom prompts from local directory
#' @param prompts_dir Directory containing custom prompts
#' @return List with custom prompts
#' @export
load_custom_prompts <- function(prompts_dir = "prompts") {
  if (!dir.exists(prompts_dir)) {
    stop("Custom prompts directory not found: ", prompts_dir)
  }
  
  prompts <- list()
  
  # Load extraction prompt if exists
  extraction_path <- file.path(prompts_dir, "extraction_prompt.md")
  if (file.exists(extraction_path)) {
    prompts$extraction <- readr::read_file(extraction_path)
  }
  
  # Load refinement prompt if exists
  refinement_path <- file.path(prompts_dir, "refinement_prompt.md")
  if (file.exists(refinement_path)) {
    prompts$refinement <- readr::read_file(refinement_path)
  }
  
  # Load context template if exists
  context_path <- file.path(prompts_dir, "extraction_context.md")
  if (file.exists(context_path)) {
    prompts$context_template <- readr::read_file(context_path)
  }
  
  cat("Loaded", length(prompts), "custom prompts from", prompts_dir, "\n")
  return(prompts)
}

#' Validate prompt templates
#' @param prompt_text Prompt text to validate
#' @return List with validation results
validate_prompt <- function(prompt_text) {
  if (is.null(prompt_text) || nchar(prompt_text) == 0) {
    return(list(valid = FALSE, issues = "Prompt is empty"))
  }
  
  issues <- character(0)
  
  # Check for common prompt elements
  if (!grepl("JSON", prompt_text, ignore.case = TRUE)) {
    issues <- c(issues, "No mention of JSON output format")
  }
  
  if (!grepl("interaction", prompt_text, ignore.case = TRUE)) {
    issues <- c(issues, "No mention of interactions")
  }
  
  # Check length (should be substantial but not too long)
  char_count <- nchar(prompt_text)
  if (char_count < 500) {
    issues <- c(issues, paste("Prompt may be too short:", char_count, "characters"))
  } else if (char_count > 10000) {
    issues <- c(issues, paste("Prompt may be too long:", char_count, "characters"))
  }
  
  return(list(
    valid = length(issues) == 0,
    issues = if (length(issues) > 0) issues else "No issues found",
    char_count = char_count
  ))
}