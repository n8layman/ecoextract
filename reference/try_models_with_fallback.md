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
  max_tokens = 64000,
  max_retries = 2,
  step_name = "LLM call",
  reasoning_prompt = NULL
)
```

## Arguments

- models:

  Character vector of model names (e.g.,
  c("anthropic/claude-sonnet-4-5", "mistral/mistral-large-latest"))

- system_prompt:

  System prompt for the LLM

- context:

  User context/input for the LLM (turn 1 message)

- schema:

  ellmer type schema for structured output (turn 2 in two-turn mode)

- max_tokens:

  Maximum tokens for response (default 64000)

- max_retries:

  Maximum retry attempts per model for stochastic failures (default 2)

- step_name:

  Name of the step for logging (default "LLM call")

- reasoning_prompt:

  When non-NULL, enables two-turn mode. This string is the turn 2 user
  message instructing the model to extract after reasoning. The turn 1
  result (reasoning) and turn 2 result (records) are combined into a
  single list returned as `result`.

## Value

List with result (structured output), model_used (which model
succeeded), and error_log (JSON string of failed attempts)

## Details

When `reasoning_prompt` is provided, a two-turn conversation is used:
turn 1 returns structured reasoning (always captured), turn 2 uses that
reasoning as context and returns the structured records. Both turns
share the same chat object so turn 1 reasoning is in context for turn 2.
On any failure, both turns are retried together with the next model.
