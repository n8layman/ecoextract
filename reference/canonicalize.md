# Deduplication Functions

Functions for semantic deduplication of extracted records using
embeddings Canonicalize text field for embedding

## Usage

``` r
canonicalize(text)
```

## Arguments

- text:

  Character vector to normalize

## Value

Normalized character vector

## Details

Normalizes text fields to improve embedding consistency: - Unicode
normalization (NFC) - Lowercase - Trim whitespace
