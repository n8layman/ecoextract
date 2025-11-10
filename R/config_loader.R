#' Load Configuration File with Priority Order
#'
#' Searches for configuration files in the following priority order:
#' 1. Explicit file path (if provided)
#' 2. Project ecoextract/ directory
#' 3. Working directory (with ecoextract_ prefix)
#' 4. Package default location
#'
#' @param file_path Explicit path to file (highest priority)
#' @param file_name Base filename to search for (e.g., "schema.json", "extraction_prompt.md")
#' @param package_subdir Subdirectory in package inst/ (e.g., "extdata", "prompts")
#' @param return_content If TRUE, returns file content; if FALSE, returns file path
#' @return File path or content, depending on return_content parameter
#' @keywords internal
load_config_file <- function(file_path = NULL,
                              file_name = NULL,
                              package_subdir = "extdata",
                              return_content = FALSE) {

  # Priority 1: Explicit file path
  if (!is.null(file_path)) {
    if (file.exists(file_path)) {
      if (return_content) {
        return(readr::read_file(file_path))
      } else {
        return(file_path)
      }
    } else {
      stop("Specified file not found: ", file_path)
    }
  }

  # Need file_name for remaining searches
  if (is.null(file_name)) {
    stop("Either file_path or file_name must be provided")
  }

  # Priority 2: Project ecoextract/ directory
  project_path <- file.path("ecoextract", file_name)
  if (file.exists(project_path)) {
    if (return_content) {
      return(readr::read_file(project_path))
    } else {
      return(project_path)
    }
  }

  # Priority 3: Working directory with ecoextract_ prefix
  wd_path <- file.path(getwd(), paste0("ecoextract_", file_name))
  if (file.exists(wd_path)) {
    if (return_content) {
      return(readr::read_file(wd_path))
    } else {
      return(wd_path)
    }
  }

  # Priority 4: Package default
  package_path <- system.file(package_subdir, file_name, package = "ecoextract")
  if (file.exists(package_path)) {
    if (return_content) {
      return(readr::read_file(package_path))
    } else {
      return(package_path)
    }
  }

  # Not found anywhere
  stop("Configuration file '", file_name, "' not found in any of the following locations:\n",
       "  1. Explicit path (none provided)\n",
       "  2. Project directory: ", project_path, "\n",
       "  3. Working directory: ", wd_path, "\n",
       "  4. Package defaults: ", package_subdir, "/", file_name)
}

#' Initialize ecoextract Project Configuration
#'
#' Creates an ecoextract/ directory in the project root and copies default
#' template files for customization. This allows users to override package
#' defaults on a per-project basis.
#'
#' @param project_dir Directory where to create ecoextract/ folder (default: current directory)
#' @param overwrite Whether to overwrite existing files
#' @return Invisibly returns TRUE if successful
#' @export
#'
#' @examples
#' \dontrun{
#' # Create ecoextract config directory with templates
#' init_ecoextract()
#'
#' # Now customize files in ecoextract/ directory:
#' # - Read SCHEMA_GUIDE.md for schema format requirements
#' # - Edit schema.json to define your data fields
#' # - Edit extraction_prompt.md to describe what to extract
#' }
init_ecoextract <- function(project_dir = getwd(), overwrite = FALSE) {

  # Create ecoextract directory
  config_dir <- file.path(project_dir, "ecoextract")
  if (!dir.exists(config_dir)) {
    dir.create(config_dir, recursive = TRUE)
    cat("Created directory:", config_dir, "\n")
  }

  # Files to copy (only domain-specific ones that users need to customize)
  # Note: context templates and refinement_prompt.md are not copied as they're generic/algorithmic
  files_to_copy <- list(
    list(source = "SCHEMA_GUIDE.md", dest = "SCHEMA_GUIDE.md", subdir = "extdata", desc = "Schema format documentation"),
    list(source = "schema.json", dest = "schema.json", subdir = "extdata", desc = "Schema definition (example)"),
    list(source = "extraction_prompt.md", dest = "extraction_prompt.md", subdir = "prompts", desc = "Extraction system prompt (example)")
  )

  copied <- 0
  skipped <- 0

  for (item in files_to_copy) {
    source_path <- system.file(item$subdir, item$source, package = "ecoextract")
    dest_path <- file.path(config_dir, item$dest)

    if (!file.exists(source_path)) {
      warning("Package file not found: ", item$source)
      next
    }

    if (file.exists(dest_path) && !overwrite) {
      cat("  [SKIP]", item$dest, "(already exists, use overwrite = TRUE)\n")
      skipped <- skipped + 1
    } else {
      file.copy(source_path, dest_path, overwrite = overwrite)
      cat("  [COPY]", item$dest, "-", item$desc, "\n")
      copied <- copied + 1
    }
  }

  cat("\nConfiguration initialized in:", config_dir, "\n")
  cat("Files copied:", copied, "| Skipped:", skipped, "\n\n")

  cat("Next steps:\n")
  cat("1. Read SCHEMA_GUIDE.md to understand the required schema format\n")
  cat("2. Edit schema.json to define your domain-specific data structure\n")
  cat("3. Edit extraction_prompt.md to describe what to extract (e.g., 'host-pathogen relationships')\n")
  cat("4. Run process_documents() - it will automatically use your custom configs\n")
  cat("5. Add ecoextract/ to version control to share with team\n\n")

  cat("Note: The package will automatically detect and use files in ecoextract/\n")
  cat("You can also place configs in working directory with 'ecoextract_' prefix\n")

  invisible(TRUE)
}
