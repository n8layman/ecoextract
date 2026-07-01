# Migrate an ecoextract database to use UUID identifiers

Converts \`records.id\` and \`record_edits.record_id\` /
\`record_edits.id\` from \`INTEGER\` to \`TEXT\` (UUID v4). Run once on
databases created with ecoextract \< 0.1.13. Safe to re-run — exits
silently if already migrated.

## Usage

``` r
migrate_ecoextract_database(db_conn)
```

## Arguments

- db_conn:

  A DBI connection object or a path to an SQLite database file.

## Value

\`NULL\` invisibly.

## Details

The migration runs inside a transaction. Foreign key enforcement is
disabled for the duration of the table recreation and restored
afterwards.
