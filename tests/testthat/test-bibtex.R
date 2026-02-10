test_that("export_bibtex extracts document metadata as BibTeX", {
  # Test exporting papers from the documents table as BibTeX entries
  db_path <- local_test_db()
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  # Add documents with various metadata completeness
  DBI::dbExecute(con, "
    INSERT INTO documents (
      file_name, file_path, file_hash, upload_timestamp,
      first_author_lastname, authors, title, journal,
      publication_year, volume, pages, doi
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    "complete.pdf", "/tmp/complete.pdf", "hash1", "2024-01-01 00:00:00",
    "Smith", '["John Smith", "Jane Doe"]',
    "Complete Article", "Test Journal",
    2023, "10", "1-10", "10.1234/test"
  ))

  DBI::dbExecute(con, "
    INSERT INTO documents (
      file_name, file_path, file_hash, upload_timestamp,
      title
    ) VALUES (?, ?, ?, ?, ?)
  ", params = list(
    "minimal.pdf", "/tmp/minimal.pdf", "hash2", "2024-01-01 00:00:00",
    "Minimal Article"
  ))

  # Export as documents (default mode)
  result <- export_bibtex(con, source = "documents")

  # Should produce valid BibTeX for both documents
  expect_type(result, "character")
  expect_true(nchar(result) > 0)

  # Complete document should have proper fields
  expect_match(result, "@article\\{Smith2023,")
  expect_match(result, "author = \\{")
  expect_match(result, "title = \\{Complete Article\\}")
  expect_match(result, "journal = \\{Test Journal\\}")
  expect_match(result, "year = \\{2023\\}")
  expect_match(result, "doi = \\{10.1234/test\\}")

  # Minimal document should still export (as @misc)
  expect_match(result, "@misc\\{Doc2NODATE,")
  expect_match(result, "title = \\{Minimal Article\\}")
})

test_that("export_bibtex extracts citations from bibliography field", {
  # Test exporting extracted citations from the bibliography field in documents table
  db_path <- local_test_db()
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  # Add document with bibliography citations
  DBI::dbExecute(con, "
    INSERT INTO documents (
      file_name, file_path, file_hash, upload_timestamp,
      first_author_lastname, publication_year,
      bibliography
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    "paper.pdf", "/tmp/paper.pdf", "hash1", "2024-01-01 00:00:00",
    "Smith", 2023,
    jsonlite::toJSON(c(
      "Jones, A. 2020. Test article. Nature 123:45-50.",
      "Brown, B. et al. 2021. Another study. Science 456:78-90."
    ))
  ))

  # Add document without bibliography field
  DBI::dbExecute(con, "
    INSERT INTO documents (
      file_name, file_path, file_hash, upload_timestamp,
      first_author_lastname, title, publication_year
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    "no-bib.pdf", "/tmp/no-bib.pdf", "hash2", "2024-01-01 00:00:00",
    "Williams", "Paper Without Citations", 2022
  ))

  # Export citations from bibliography field
  result <- export_bibtex(con, source = "citations")

  # Should have citation entries from first document
  expect_type(result, "character")
  expect_true(nchar(result) > 0)
  expect_match(result, "@[a-z]+\\{Smith2023_cit1,")
  expect_match(result, "@[a-z]+\\{Smith2023_cit2,")

  # Should extract years from citation text
  expect_match(result, "year = \\{2020\\}")
  expect_match(result, "year = \\{2021\\}")

  # Export from specific document
  result_single <- export_bibtex(con, document_ids = 1, source = "citations")
  expect_true(nchar(result_single) > 0)
  expect_match(result_single, "Smith2023_cit")
})
