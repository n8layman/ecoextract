# Calculate Jaccard similarity between two strings

Tokenizes strings into character n-grams and calculates Jaccard
similarity. This is a fast, non-API-dependent method for string
comparison.

## Usage

``` r
jaccard_similarity(str1, str2, n = 3)
```

## Arguments

- str1:

  First string

- str2:

  Second string

- n:

  N-gram size (default: 3 for trigrams)

## Value

Numeric similarity score (0-1)
