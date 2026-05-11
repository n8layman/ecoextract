# Detect whether an LLM error is a content refusal

When a model refuses content (e.g. papers about select agents), it may
truncate structured output early rather than returning an explicit
refusal signal. This produces parse errors indistinguishable from
network issues. This function checks for refusal indicators in the error
and response.

## Usage

``` r
is_content_refusal(error_msg, raw_content = NULL, stop_reason = NULL)
```

## Arguments

- error_msg:

  The error message string

- raw_content:

  Raw response content from the API (may be NULL)

- stop_reason:

  The stop_reason from the API response (may be NULL)

## Value

Logical
