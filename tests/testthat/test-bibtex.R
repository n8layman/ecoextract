test_that("export_bibtex creates valid BibTeX entries", {
  # Create temporary database
  db <- local_test_db()

  # Add a test document with metadata
  DBI::dbExecute(db, "
    INSERT INTO documents (
      file_name, file_path, file_hash, upload_timestamp,
      first_author_lastname, authors, title, journal,
      publication_year, volume, pages, doi
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    "test.pdf", "/tmp/test.pdf", "hash123", "2024-01-01 00:00:00",
    "Smith", '["John Smith", "Jane Doe"]',
    "Test Article", "Test Journal",
    2023, "10", "1-10", "10.1234/test"
  ))

  # Export BibTeX
  result <- export_bibtex(db)

  # Check structure
  expect_type(result, "character")
  expect_true(nchar(result) > 0)

  # Check BibTeX format
  expect_match(result, "@article\\{Smith2023,")
  expect_match(result, "author = \\{")
  expect_match(result, "title = \\{Test Article\\}")
  expect_match(result, "journal = \\{Test Journal\\}")
  expect_match(result, "year = \\{2023\\}")
  expect_match(result, "doi = \\{10.1234/test\\}")
})

test_that("export_bibtex handles missing fields gracefully", {
  db <- local_test_db()

  # Add document with minimal metadata
  DBI::dbExecute(db, "
    INSERT INTO documents (
      file_name, file_path, file_hash, upload_timestamp,
      title
    ) VALUES (?, ?, ?, ?, ?)
  ", params = list(
    "test.pdf", "/tmp/test.pdf", "hash123", "2024-01-01 00:00:00",
    "Minimal Article"
  ))

  # Should not error
  result <- export_bibtex(db)

  expect_type(result, "character")
  expect_match(result, "@misc\\{Doc1NODATE,")
  expect_match(result, "title = \\{Minimal Article\\}")
})

test_that("export_bibtex filters by document_ids", {
  db <- local_test_db()

  # Add multiple documents
  for (i in 1:3) {
    DBI::dbExecute(db, "
      INSERT INTO documents (
        file_name, file_path, file_hash, upload_timestamp,
        first_author_lastname, title, publication_year
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      paste0("test", i, ".pdf"),
      paste0("/tmp/test", i, ".pdf"),
      paste0("hash", i),
      "2024-01-01 00:00:00",
      paste0("Author", i),
      paste0("Title ", i),
      2020 + i
    ))
  }

  # Export only document 2
  result <- export_bibtex(db, document_ids = 2)

  # Should only contain one entry
  entry_count <- length(gregexpr("@", result)[[1]])
  expect_equal(entry_count, 1)
  expect_match(result, "Author2")
  expect_match(result, "Title 2")
})

test_that("export_bibtex handles duplicate citation keys", {
  db <- local_test_db()

  # Add two documents by same author and year
  for (i in 1:2) {
    DBI::dbExecute(db, "
      INSERT INTO documents (
        file_name, file_path, file_hash, upload_timestamp,
        first_author_lastname, title, publication_year
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      paste0("test", i, ".pdf"),
      paste0("/tmp/test", i, ".pdf"),
      paste0("hash", i),
      "2024-01-01 00:00:00",
      "Smith",
      paste0("Article ", i),
      2023
    ))
  }

  result <- export_bibtex(db)

  # Should have unique keys with suffixes
  expect_match(result, "@[a-z]+\\{Smith2023a,")
  expect_match(result, "@[a-z]+\\{Smith2023b,")
})

test_that("export_bibtex writes to file", {
  db <- local_test_db()

  # Add a document
  DBI::dbExecute(db, "
    INSERT INTO documents (
      file_name, file_path, file_hash, upload_timestamp,
      first_author_lastname, title, publication_year
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    "test.pdf", "/tmp/test.pdf", "hash123", "2024-01-01 00:00:00",
    "Jones", "Test Title", 2024
  ))

  # Export to temporary file
  tmp_file <- withr::local_tempfile(fileext = ".bib")
  result <- export_bibtex(db, filename = tmp_file)

  # File should exist and contain BibTeX
  expect_true(file.exists(tmp_file))
  file_content <- readLines(tmp_file)
  expect_true(any(grepl("@article\\{Jones2024,", file_content)))
})

test_that("export_bibtex accepts both connection and path", {
  db_path <- withr::local_tempfile(fileext = ".db")

  # Initialize database
  init_ecoextract_database(db_path)

  # Add a document
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  DBI::dbExecute(con, "
    INSERT INTO documents (
      file_name, file_path, file_hash, upload_timestamp,
      first_author_lastname, title, publication_year
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    "test.pdf", "/tmp/test.pdf", "hash123", "2024-01-01 00:00:00",
    "Brown", "Test Article", 2024
  ))

  # Test with connection object
  result1 <- export_bibtex(con)
  expect_match(result1, "Brown2024")

  # Test with path string
  result2 <- export_bibtex(db_path)
  expect_match(result2, "Brown2024")

  # Should produce same output
  expect_equal(result1, result2)
})

test_that("export_bibtex returns empty string for no documents", {
  db <- local_test_db()

  # Export from empty database
  result <- export_bibtex(db)

  expect_equal(result, "")
})

test_that("export_bibtex exports citations from bibliography field", {
  db <- local_test_db()

  # Add a document with bibliography citations
  DBI::dbExecute(db, "
    INSERT INTO documents (
      file_name, file_path, file_hash, upload_timestamp,
      first_author_lastname, publication_year,
      bibliography
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    "test.pdf", "/tmp/test.pdf", "hash123", "2024-01-01 00:00:00",
    "Smith", 2023,
    jsonlite::toJSON(c(
      "Jones, A. 2020. Test article. Nature 123:45-50.",
      "Brown, B. et al. 2021. Another study. Science 456:78-90."
    ))
  ))

  # Export citations
  result <- export_bibtex(db, source = "citations")

  # Check structure
  expect_type(result, "character")
  expect_true(nchar(result) > 0)

  # Should have citation entries
  expect_match(result, "@[a-z]+\\{Smith2023_cit1,")
  expect_match(result, "@[a-z]+\\{Smith2023_cit2,")

  # Should extract years
  expect_match(result, "year = \\{2020\\}")
  expect_match(result, "year = \\{2021\\}")
})

test_that("export_bibtex handles documents without bibliography", {
  db <- local_test_db()

  # Add document without bibliography
  DBI::dbExecute(db, "
    INSERT INTO documents (
      file_name, file_path, file_hash, upload_timestamp,
      first_author_lastname, title, publication_year
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    "test.pdf", "/tmp/test.pdf", "hash123", "2024-01-01 00:00:00",
    "Smith", "Test Title", 2023
  ))

  # Export citations should return empty
  result <- export_bibtex(db, source = "citations")

  expect_equal(result, "")
})

test_that("parse_citation_text extracts year and doi", {
  citation <- "Smith, J. 2023. Test article. Nature 10:123-456. doi:10.1234/test"

  parsed <- ecoextract:::parse_citation_text(citation)

  expect_equal(parsed$year, "2023")
  expect_match(parsed$doi, "10.1234/test")
})
