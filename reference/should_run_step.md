# Determine if a processing step should run

Determine if a processing step should run

## Usage

``` r
should_run_step(status, data_exists)
```

## Arguments

- status:

  Current status value for this step

- data_exists:

  Logical or NULL. If logical, checks for desync (status="completed" but
  data missing). Pass NULL to skip desync check.

## Value

logical - TRUE if step should run, FALSE to skip
