#' Prompt Management Functions
#' 
#' Handle system prompts and templates for ecological data extraction

#' Get extraction prompt from package or custom location
#' @param prompt_file Optional path to custom extraction prompt file
#' @return Character string with extraction prompt
#' @export
get_extraction_prompt <- function(prompt_file = NULL) {
  load_config_file(
    file_path = prompt_file,
    file_name = "extraction_prompt.md",
    package_subdir = "prompts",
    return_content = TRUE
  )
}

#' Get refinement prompt from package or custom location
#' @param prompt_file Optional path to custom refinement prompt file
#' @return Character string with refinement prompt
#' @export
get_refinement_prompt <- function(prompt_file = NULL) {
  load_config_file(
    file_path = prompt_file,
    file_name = "refinement_prompt.md",
    package_subdir = "prompts",
    return_content = TRUE
  )
}

#' Get OCR audit prompt from package or custom location
#' @param prompt_file Optional path to custom OCR audit prompt file
#' @return Character string with OCR audit prompt
#' @export
get_ocr_audit_prompt <- function(prompt_file = NULL) {
  load_config_file(
    file_path = prompt_file,
    file_name = "ocr_audit_prompt.md",
    package_subdir = "prompts",
    return_content = TRUE
  )
}

#' Get extraction context template from package or custom location
#' @param context_file Optional path to custom context template file
#' @return Character string with context template
#' @export
get_extraction_context_template <- function(context_file = NULL) {
  load_config_file(
    file_path = context_file,
    file_name = "extraction_context.md",
    package_subdir = "prompts",
    return_content = TRUE
  )
}

