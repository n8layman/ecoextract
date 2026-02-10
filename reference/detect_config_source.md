# Detect Configuration File Source

Determines where a config file would be loaded from without loading it.
Returns a list with source type and path.

## Usage

``` r
detect_config_source(
  file_path = NULL,
  file_name = NULL,
  package_subdir = "extdata"
)
```

## Arguments

- file_path:

  Explicit path to file (highest priority)

- file_name:

  Base filename to search for

- package_subdir:

  Subdirectory in package inst/

## Value

List with source ("explicit", "project", "wd", "package") and path
