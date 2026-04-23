# Database Tests
# Tests for database initialization, schema, save/retrieve, and array field handling

# process_documents input validation -------------------------------------------

test_that("process_documents errors when both pdf_path and document_id given", {
  expect_error(
    process_documents(pdf_path = "some.pdf", document_id = 1L),
    "mutually exclusive"
  )
})

test_that("process_documents errors when neither pdf_path nor document_id given", {
  expect_error(
    process_documents(),
    "One of pdf_path or document_id must be provided"
  )
})

test_that("process_documents errors when pdf_path vector contains a directory", {
  tmp_dir <- withr::local_tempdir()
  tmp_pdf <- withr::local_tempfile(fileext = ".pdf")
  writeLines("fake pdf", tmp_pdf)
  expect_error(
    process_documents(pdf_path = c(tmp_pdf, tmp_dir)),
    "must contain only PDF files, not directories"
  )
})

test_that("process_documents with document_id errors if none found in db", {
  db_path <- local_test_db()
  expect_error(
    process_documents(document_id = 99L, db_conn = db_path),
    "No documents found in database"
  )
})

# Database Core ----------------------------------------------------------------

test_that("database initialization creates required tables", {
  db_path <- local_test_db()

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  tables <- DBI::dbListTables(con)
  expect_true("documents" %in% tables)
  expect_true("records" %in% tables)
})

test_that("database initialization creates record_edits table", {
  db_path <- local_test_db()

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  tables <- DBI::dbListTables(con)
  expect_true("record_edits" %in% tables)

  # Verify table structure
  cols <- DBI::dbListFields(con, "record_edits")
  expect_true("record_id" %in% cols)
  expect_true("column_name" %in% cols)
  expect_true("original_value" %in% cols)
  expect_true("edited_at" %in% cols)
})

test_that("database schema matches JSON schema definition", {
  db_path <- local_test_db()
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  db_columns <- DBI::dbListFields(con, "records")
  schema_columns <- get_db_schema_columns()

  # Database should contain all schema columns
  expect_true(all(schema_columns %in% db_columns))
})

test_that("save and retrieve records workflow", {
  db_path <- local_test_db()

  # Create temporary test file
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)

  # Save document (hash computed automatically)
  doc_id <- save_document_to_db(db_path, test_file)
  expect_type(doc_id, "integer")

  # Save records (will throw error if it fails)
  records <- sample_records()
  save_records_to_db(db_path, doc_id, records, list())

  # Verify saved
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  saved <- DBI::dbReadTable(con, "records")
  expect_equal(nrow(saved), nrow(records))
})

# Array Field Handling ----------------------------------------------------------

test_that("get_schema_array_fields identifies array fields", {
  schema_path <- load_config_file(NULL, "schema.json", "extdata", return_content = FALSE)
  schema_json <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
  schema_list <- jsonlite::fromJSON(schema_json, simplifyVector = FALSE)

  array_fields <- get_schema_array_fields(schema_list)
  expect_true(length(array_fields) > 0)
  expect_true("all_supporting_source_sentences" %in% array_fields)
})

test_that("get_schema_array_fields returns empty for no-array schema", {
  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          properties = list(
            name = list(type = "string"),
            count = list(type = "integer")
          )
        )
      )
    )
  )

  result <- get_schema_array_fields(schema_list)
  expect_equal(length(result), 0)
})

test_that("normalize_array_fields validates required fields", {
  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          required = c("tags"),
          properties = list(
            tags = list(type = "array", items = list(type = "string"))
          )
        )
      )
    )
  )

  # Missing required array field should error
  df <- tibble::tibble(tags = list(NULL))
  expect_error(normalize_array_fields(df, schema_list), "Required field")
})

test_that("normalize_array_fields passes through data unmodified", {
  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          properties = list(
            tags = list(type = "array", items = list(type = "string"))
          )
        )
      )
    )
  )

  # Data should pass through unmodified (normalization happens in serialization)
  df <- tibble::tibble(tags = list(c("a", "b")))
  result <- normalize_array_fields(df, schema_list)
  expect_equal(result$tags[[1]], c("a", "b"))
})

test_that("array fields stored as single-level JSON arrays in database", {
  db_path <- local_test_db()

  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)

  # Load schema for array field awareness
  schema_path <- load_config_file(NULL, "schema.json", "extdata", return_content = FALSE)
  schema_json <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
  schema_list <- jsonlite::fromJSON(schema_json, simplifyVector = FALSE)

  # Create records with array field as a list column (how ellmer returns data)
  records <- sample_records()
  records$all_supporting_source_sentences <- list(
    c("Sentence one.", "Sentence two."),
    c("Single sentence.")
  )

  save_records_to_db(db_path, doc_id, records, list(), schema_list = schema_list)

  # Read raw values from database
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  saved <- DBI::dbReadTable(con, "records")

  # Verify single-level JSON arrays (not double-nested)
  multi <- saved$all_supporting_source_sentences[1]
  single <- saved$all_supporting_source_sentences[2]

  expect_equal(multi, '["Sentence one.","Sentence two."]')
  expect_equal(single, '["Single sentence."]')
})
