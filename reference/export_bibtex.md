# Export Bibliography to BibTeX Format

Converts bibliography entries from the database to BibTeX format for use
with LaTeX and reference managers. Can export either document metadata
(the papers themselves) or extracted citations (references from those
papers).

## Usage

``` r
export_bibtex(
  db_conn,
  document_ids = NULL,
  filename = NULL,
  source = c("documents", "citations")
)
```

## Arguments

- db_conn:

  Database connection or path to SQLite database file

- document_ids:

  Optional vector of document IDs to export (default: all documents)

- filename:

  Optional output file path (e.g., "references.bib"). If NULL, returns
  BibTeX string without writing to file.

- source:

  What to export: "documents" exports metadata for the papers
  themselves, "citations" exports the references extracted from those
  papers (stored in bibliography field). Default: "documents".

## Value

Character string containing BibTeX entries (invisibly if filename
provided)

## Examples

``` r
if (FALSE) { # \dontrun{
# Export document metadata (the papers themselves)
export_bibtex(db_conn = "records.db", filename = "papers.bib")

# Export extracted citations from papers
export_bibtex(db_conn = "records.db", source = "citations",
              filename = "citations.bib")

# Export citations from specific documents
export_bibtex(db_conn = "records.db", document_ids = c(1, 5, 10),
              source = "citations")

# Get BibTeX as string
bib_text <- export_bibtex(db_conn = "records.db")
cat(bib_text)
} # }
```
