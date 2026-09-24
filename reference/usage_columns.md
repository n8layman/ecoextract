# Token usage column names for a pipeline step (internal)

Token usage column names for a pipeline step (internal)

## Usage

``` r
usage_columns(step)
```

## Arguments

- step:

  LLM step name ("metadata", "extraction", or "refinement")

## Value

Character vector of documents table column names, in the order of the
fields returned by
[`chat_usage()`](https://n8layman.github.io/ecoextract/reference/chat_usage.md)
