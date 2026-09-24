# Resolve a stored file path against the project root

Inverse of
[`to_project_relative_path()`](https://n8layman.github.io/ecoextract/reference/to_project_relative_path.md):
a project-relative path from the database is joined to the project root
found by walking up from the working directory, so documents resolve
from any subdirectory of the project. Absolute paths, and paths when no
project root is found, are returned unchanged.

## Usage

``` r
from_project_relative_path(file_path)
```

## Arguments

- file_path:

  Stored file path

## Value

File path usable from the working directory
