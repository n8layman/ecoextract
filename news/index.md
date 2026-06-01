# Changelog

## ecoextract 0.1.8

### Improvements

- Extraction now uses a two-turn LLM conversation: turn 1 produces
  structured reasoning (capturing document analysis, organism
  identifiability decisions, and extraction choices), turn 2 uses that
  reasoning as context to extract structured records. This ensures
  reasoning causally precedes extraction rather than being a sibling
  field in the same structured output call, fixing divergence between
  stated reasoning and extracted records.

- `reasoning` removed from the extraction JSON schema — it is now always
  captured via the two-turn structure and stored in the database
  regardless of schema configuration.

- Content refusals on turn 1 are now correctly detected and logged as
  refusals rather than retried as stochastic empty-reasoning failures.

## ecoextract 0.1.7

- Initial release.
