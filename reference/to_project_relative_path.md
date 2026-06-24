# Convert a file path to project-relative form for database storage

Uses
[`find_project_root()`](https://n8layman.github.io/ecoextract/reference/find_project_root.md)
starting from the file's own directory, so the root is always anchored
to the PDF project — not the `.db` location or the working directory.
Falls back to an absolute path when no project root is found.

## Usage

``` r
to_project_relative_path(file_path)
```
