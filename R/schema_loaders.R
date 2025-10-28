#' Load Custom Schema from JSON File
#'
#' Load a custom interaction schema from a JSON file and convert it to an ellmer Type object.
#'
#' @param schema_file Path to JSON schema file. If NULL, uses default schema.
#' @param schema_type Type of schema to load: "extraction" or "refinement"
#' @return ellmer type object for structured data extraction
#' @export
#'
#' @examples
#' \dontrun{
#' # Use default schema
#' schema <- load_schema()
#'
#' # Load from custom JSON file
#' schema <- load_schema("my_custom_schema.json")
#'
#' # Export default schema to customize
#' export_schema_template("my_schema.json")
#' }
load_schema <- function(schema_file = NULL, schema_type = c("extraction", "refinement")) {
  schema_type <- match.arg(schema_type)

  # Use config loader to find schema file with priority order
  schema_path <- load_config_file(
    file_path = schema_file,
    file_name = "schema.json",
    package_subdir = "extdata",
    return_content = FALSE
  )

  # Load JSON schema
  tryCatch({
    json_data <- jsonlite::fromJSON(schema_path, simplifyVector = FALSE)

    # Create ellmer Type from JSON Schema
    schema <- ellmer::TypeJsonSchema(
      description = json_data$description %||% paste("Custom", schema_type, "schema"),
      json = json_data
    )

    return(schema)
  }, error = function(e) {
    stop("Error loading JSON schema from '", schema_path, "': ", e$message)
  })
}

#' Export Default Schema Template to JSON File
#'
#' Export the default interaction schema to a JSON file for customization.
#'
#' @param output_file Path to output JSON file
#' @param schema_type Type of schema to export: "extraction" or "refinement"
#' @param overwrite Whether to overwrite existing file
#' @return Invisibly returns TRUE on success
#' @export
#'
#' @examples
#' \dontrun{
#' # Export extraction schema template
#' export_schema_template("my_schema.json")
#'
#' # Export refinement schema template
#' export_schema_template("my_refinement.json", schema_type = "refinement")
#' }
export_schema_template <- function(output_file,
                                   schema_type = c("extraction", "refinement"),
                                   overwrite = FALSE) {
  schema_type <- match.arg(schema_type)

  # Check if file exists and overwrite is FALSE
  if (file.exists(output_file) && !overwrite) {
    stop("File already exists: ", output_file, ". Use overwrite = TRUE to replace it.")
  }

  # Get the default schema source
  schema_source_file <- system.file("extdata", "interaction_schema.json", package = "ecoextract")

  if (!file.exists(schema_source_file)) {
    stop("Default schema template not found. This shouldn't happen - please report as a bug.")
  }

  # Copy the JSON file
  file.copy(schema_source_file, output_file, overwrite = overwrite)

  message("Exported default ", schema_type, " schema to: ", output_file)
  message("\nNext steps:")
  message("1. Edit ", output_file, " to customize fields")
  message("2. Load with: extract_records(..., schema_file = '", output_file, "')")
  message("\nJSON Schema documentation: https://json-schema.org/understanding-json-schema/")

  invisible(TRUE)
}
