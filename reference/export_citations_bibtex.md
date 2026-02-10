# Export Citations from Bibliography Field

Exports citations extracted from papers (stored in bibliography column)
to BibTeX format.

## Usage

``` r
export_citations_bibtex(con, document_ids = NULL, filename = NULL)
```

## Arguments

- con:

  Database connection object

- document_ids:

  Optional vector of document IDs

- filename:

  Optional output file path

## Value

Character string containing BibTeX entries
