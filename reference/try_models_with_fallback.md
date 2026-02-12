# Try multiple LLM models with fallback on refusal

Attempts to get structured output from LLMs in sequential order. If a
model refuses (stop_reason == "refusal") or errors, tries the next
model.

## Usage

``` r
try_models_with_fallback(
  models,
  system_prompt,
  context,
  schema,
  max_tokens = 16384,
  step_name = "LLM call"
)
```

## Arguments

- models:

  Character vector of model names (e.g.,
  c("anthropic/claude-sonnet-4-5", "mistral/mistral-large-latest"))

- system_prompt:

  System prompt for the LLM

- context:

  User context/input for the LLM

- schema:

  ellmer type schema for structured output

- max_tokens:

  Maximum tokens for response (default 16384)

- step_name:

  Name of the step for logging (default "LLM call")

## Value

List with result (structured output), model_used (which model
succeeded), and error_log (JSON string of failed attempts)
