# Try multiple LLM models with fallback on refusal

Attempts to get structured output from LLMs in sequential order. If a
model refuses (stop_reason == "refusal") or errors, tries the next
model.

## Usage

``` r
inject_additional_properties(schema_list)
```

## Arguments

- schema_list:

  Parsed JSON schema as an R list

- models:

  Character vector of model names (e.g.,
  c("anthropic/claude-sonnet-4-5", "mistral/mistral-large-latest"))

- system_prompt:

  System prompt for the LLM Inject additionalProperties: false into a
  JSON schema

  Recursively adds \`additionalProperties = FALSE\` to every object
  definition in a parsed JSON schema. Required by OpenAI's structured
  outputs API. Safe for all providers.

## Value

The schema list with additionalProperties: false injected
