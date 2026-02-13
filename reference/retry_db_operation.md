# Retry database operation with exponential backoff

Wraps a database operation with retry logic to handle temporary locks.

## Usage

``` r
retry_db_operation(expr, max_attempts = 3, initial_wait = 0.5)
```

## Arguments

- expr:

  Expression to evaluate (database operation)

- max_attempts:

  Maximum number of retry attempts (default: 3)

- initial_wait:

  Initial wait time in seconds (default: 0.5)

## Value

Result of the expression
