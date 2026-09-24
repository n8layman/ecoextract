# Token usage of a chat (internal)

Sums the token counts ellmer records for each completed assistant turn.
`input_tokens` includes tokens written to the prompt cache;
`cached_input_tokens` are tokens read from it.

## Usage

``` r
chat_usage(chat)
```

## Arguments

- chat:

  An ellmer Chat object

## Value

Named list with input_tokens, output_tokens, and cached_input_tokens
