# Provider API arguments for an LLM call (internal)

Claude runs adaptive thinking when the request doesn't say otherwise,
and ellmer's params cannot turn it off, so thinking is disabled in the
request body unless `reasoning_effort` is set.

## Usage

``` r
llm_api_args(model, reasoning_effort = NULL)
```

## Arguments

- model:

  Model name in "provider/model" form

- reasoning_effort:

  Thinking effort, or NULL for thinking off

## Value

List of extra request body fields, passed as `api_args`
