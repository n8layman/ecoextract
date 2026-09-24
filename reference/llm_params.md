# Build ellmer params for an LLM call (internal)

With `reasoning_effort` set, thinking runs at that effort. Without it,
thinking is turned off where ellmer's params can express that: Gemini
gets `reasoning_tokens = 0`. Claude's thinking is turned off through
[`llm_api_args()`](https://n8layman.github.io/ecoextract/reference/llm_api_args.md)
instead, because ellmer has no param for it.

## Usage

``` r
llm_params(model, max_tokens, reasoning_effort = NULL)
```

## Arguments

- model:

  Model name in "provider/model" form

- max_tokens:

  Maximum tokens for the response

- reasoning_effort:

  Thinking effort, or NULL for thinking off

## Value

ellmer params list
