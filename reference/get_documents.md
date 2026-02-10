# Get Documents

Retrieve documents from the database

## Usage

``` r
get_documents(document_id = NULL, db_conn = "ecoextract_records.db")
```

## Arguments

- document_id:

  Document ID to filter by (NULL for all documents)

- db_conn:

  Database connection (any DBI backend) or path to SQLite database file.
  Defaults to "ecoextract_records.db"

## Value

Tibble with document metadata

## Examples

``` r
if (FALSE) { # \dontrun{
# Using default SQLite database
all_docs <- get_documents()
doc <- get_documents(document_id = 1)

# Using explicit connection
db <- DBI::dbConnect(RSQLite::SQLite(), "ecoextract.sqlite")
all_docs <- get_documents(db_conn = db)
doc <- get_documents(document_id = 1, db_conn = db)
DBI::dbDisconnect(db)
} # }
```
