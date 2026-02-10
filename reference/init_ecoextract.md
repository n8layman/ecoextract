# Initialize ecoextract Project Configuration

Creates an ecoextract/ directory in the project root and copies default
template files for customization. This allows users to override package
defaults on a per-project basis.

## Usage

``` r
init_ecoextract(project_dir = getwd(), overwrite = FALSE)
```

## Arguments

- project_dir:

  Directory where to create ecoextract/ folder (default: current
  directory)

- overwrite:

  Whether to overwrite existing files

## Value

Invisibly returns TRUE if successful

## Examples

``` r
if (FALSE) { # \dontrun{
# Create ecoextract config directory with templates
init_ecoextract()

# Now customize files in ecoextract/ directory:
# - Read SCHEMA_GUIDE.md for schema format requirements
# - Edit schema.json to define your data fields
# - Edit extraction_prompt.md to describe what to extract
} # }
```
