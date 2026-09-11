# Metadata Schema Tests
# Tests for project-level metadata schemas and record IDs built from them

# Schema Loading ---------------------------------------------------------------

test_that("load_metadata_schema uses project ecoextract/ override", {
  local_custom_metadata_schema()

  fields <- get_metadata_fields(load_metadata_schema())

  expect_setequal(names(fields), c("doc_code", "doc_number", "doc_tags"))
})

test_that("load_metadata_schema prefers an explicit file over ecoextract/", {
  local_custom_metadata_schema()
  explicit <- withr::local_tempfile(fileext = ".json")
  file.copy(system.file("extdata", "metadata_schema.json", package = "ecoextract"), explicit)

  fields <- get_metadata_fields(load_metadata_schema(explicit))

  expect_false("doc_code" %in% names(fields))
})

test_that("package metadata schema names record ID fields", {
  schema_list <- jsonlite::fromJSON(
    system.file("extdata", "metadata_schema.json", package = "ecoextract"),
    simplifyVector = FALSE
  )

  id_fields <- get_record_id_fields(schema_list)

  expect_type(id_fields, "character")
  expect_true(all(id_fields %in% names(get_metadata_fields(schema_list))))
})

test_that("package metadata schema stays within structured output limits", {
  # Older models (e.g. Claude Sonnet 4.6) cap optional fields at 12 and
  # union-typed (nullable) fields at 16 (issue #142)
  schema_list <- jsonlite::fromJSON(
    system.file("extdata", "metadata_schema.json", package = "ecoextract"),
    simplifyVector = FALSE
  )
  fields <- get_metadata_fields(schema_list)
  required <- unlist(schema_list$properties$publication_metadata$required)
  n_union <- sum(purrr::map_int(fields, function(spec) length(spec$type) > 1))

  expect_setequal(required, names(fields))
  expect_lte(n_union, 16)
})

test_that("get_record_id_fields accepts document_id and file_name", {
  local_custom_metadata_schema(id_fields = list("document_id", "file_name"))

  expect_equal(get_record_id_fields(load_metadata_schema()), c("document_id", "file_name"))
})

test_that("get_record_id_fields errors when x-record-id-fields is missing", {
  local_custom_metadata_schema(id_fields = NULL)

  expect_error(get_record_id_fields(load_metadata_schema()), "x-record-id-fields")
})

test_that("get_record_id_fields errors for fields not in the metadata schema", {
  local_custom_metadata_schema(id_fields = list("doc_code", "not_a_field"))

  expect_error(get_record_id_fields(load_metadata_schema()), "not_a_field")
})

test_that("get_metadata_fields errors without publication_metadata properties", {
  expect_error(
    get_metadata_fields(list(properties = list())),
    "publication_metadata"
  )
})

# Documents Table Columns ------------------------------------------------------

test_that("init_ecoextract_database adds custom metadata columns", {
  local_custom_metadata_schema()
  db_path <- local_test_db()

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  info <- DBI::dbGetQuery(con, "PRAGMA table_info(documents)")

  expect_true(all(c("doc_code", "doc_number", "doc_tags") %in% info$name))
  expect_equal(info$type[info$name == "doc_number"], "INTEGER")
  expect_equal(info$type[info$name == "doc_tags"], "TEXT")
})

test_that("init_ecoextract_database adds columns from an explicit metadata schema", {
  schema_path <- file.path(local_custom_metadata_schema(), "ecoextract", "metadata_schema.json")
  withr::local_dir(withr::local_tempdir())  # leave the project so only the explicit file applies
  db_path <- withr::local_tempfile(fileext = ".sqlite")

  init_ecoextract_database(db_path, metadata_schema_file = schema_path)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  expect_true("doc_code" %in% DBI::dbListFields(con, "documents"))
})

test_that("add_metadata_columns adds columns to an existing database", {
  db_path <- local_test_db()
  local_custom_metadata_schema()

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  add_metadata_columns(con, load_metadata_schema())

  expect_true(all(c("doc_code", "doc_number", "doc_tags") %in%
                    DBI::dbListFields(con, "documents")))
})

test_that("add_metadata_columns is a no-op when columns already exist", {
  local_custom_metadata_schema()
  db_path <- local_test_db()

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  before <- DBI::dbListFields(con, "documents")
  add_metadata_columns(con, load_metadata_schema())

  expect_equal(DBI::dbListFields(con, "documents"), before)
})

# Saving Metadata --------------------------------------------------------------

test_that("save_metadata_to_db writes custom metadata fields", {
  local_custom_metadata_schema()
  db_path <- local_test_db()
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)

  save_metadata_to_db(doc_id, db_path, metadata = list(
    doc_code = "A-1", doc_number = 42L, doc_tags = '["x","y"]'
  ))

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  doc <- DBI::dbGetQuery(con,
    "SELECT doc_code, doc_number, doc_tags FROM documents WHERE document_id = ?",
    params = list(doc_id))

  expect_equal(doc$doc_code, "A-1")
  expect_equal(doc$doc_number, 42L)
  expect_equal(jsonlite::fromJSON(doc$doc_tags), c("x", "y"))
})

test_that("save_metadata_to_db keeps existing values when new value is missing", {
  local_custom_metadata_schema()
  db_path <- local_test_db()
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)

  save_metadata_to_db(doc_id, db_path, metadata = list(doc_code = "A-1", doc_number = 42L))
  save_metadata_to_db(doc_id, db_path, metadata = list(doc_code = NULL, doc_number = 7L))

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  doc <- DBI::dbGetQuery(con,
    "SELECT doc_code, doc_number FROM documents WHERE document_id = ?",
    params = list(doc_id))

  expect_equal(doc$doc_code, "A-1")
  expect_equal(doc$doc_number, 7L)
})

# Workflow ---------------------------------------------------------------------

#' Save a document that has completed OCR, so the workflow starts at metadata
local_ocr_document <- function(db_path, env = parent.frame()) {
  test_file <- withr::local_tempfile(fileext = ".pdf", .local_envir = env)
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file, metadata = list(document_content = "Document text"))
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  DBI::dbExecute(con, "UPDATE documents SET ocr_status = 'completed' WHERE document_id = ?",
                 params = list(doc_id))
  DBI::dbDisconnect(con)
  test_file
}

test_that("process_single_document skips metadata when run_metadata is FALSE", {
  db_path <- local_test_db()
  test_file <- local_ocr_document(db_path)
  local_mocked_bindings(extract_metadata = function(...) stop("metadata step should not run"))

  result <- process_single_document(test_file, db_path, run_metadata = FALSE, run_extraction = FALSE)

  expect_equal(result$metadata_status, "skipped")
})

test_that("process_single_document passes metadata schema and prompt files to extract_metadata", {
  db_path <- local_test_db()
  test_file <- local_ocr_document(db_path)
  schema_path <- withr::local_tempfile(fileext = ".json")
  file.copy(system.file("extdata", "metadata_schema.json", package = "ecoextract"), schema_path)
  prompt_path <- withr::local_tempfile(fileext = ".md")
  writeLines("Custom metadata prompt", prompt_path)

  captured <- new.env()
  local_mocked_bindings(extract_metadata = function(document_id, db_conn, model,
                                                    metadata_schema_file, metadata_prompt_file, ...) {
    captured$schema <- metadata_schema_file
    captured$prompt <- metadata_prompt_file
    list(status = "completed", document_id = document_id)
  })

  process_single_document(test_file, db_path,
                          metadata_schema_file = schema_path,
                          metadata_prompt_file = prompt_path,
                          run_extraction = FALSE)

  expect_equal(captured$schema, schema_path)
  expect_equal(captured$prompt, prompt_path)
})

# Record IDs -------------------------------------------------------------------

test_that("save_records_to_db builds record IDs from x-record-id-fields", {
  local_custom_metadata_schema()
  db_path <- local_test_db()
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)
  save_metadata_to_db(doc_id, db_path, metadata = list(doc_code = "A-1", doc_number = 42L))

  save_records_to_db(db_path, doc_id, sample_records(), list())

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  ids <- DBI::dbGetQuery(con, "SELECT record_id FROM records ORDER BY record_id")$record_id

  expect_equal(ids, c("A1_42_1_r1", "A1_42_1_r2"))
})

test_that("get_record_id_prefix uses document_id and file_name without extension", {
  local_custom_metadata_schema(id_fields = list("file_name", "document_id"))
  db_path <- local_test_db()
  test_file <- file.path(withr::local_tempdir(), "Report 2024-01.pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))

  expect_equal(get_record_id_prefix(con, doc_id), paste0("Report202401_", doc_id, "_1"))
})

test_that("save_records_to_db numbers new records after existing ones", {
  db_path <- local_test_db()
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)

  save_records_to_db(db_path, doc_id, sample_records(), list())
  save_records_to_db(db_path, doc_id, sample_records(), list())

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  ids <- DBI::dbGetQuery(con, "SELECT record_id FROM records")$record_id

  expect_length(unique(ids), 4)
  expect_setequal(sub(".*_r", "", ids), c("1", "2", "3", "4"))
})

test_that("save_records_to_db keeps record IDs that already belong to the document", {
  db_path <- local_test_db()
  test_file <- withr::local_tempfile(fileext = ".pdf")
  writeLines("test content", test_file)
  doc_id <- save_document_to_db(db_path, test_file)
  save_records_to_db(db_path, doc_id, sample_records(), list())

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  withr::defer(DBI::dbDisconnect(con))
  saved <- DBI::dbGetQuery(con, "SELECT * FROM records")

  # Refinement passes existing records back with their ids and record_ids
  expect_message(
    save_records_to_db(con, doc_id, saved, list(), mode = "update"),
    "Preserving existing record IDs for 2 records"
  )
  after <- DBI::dbGetQuery(con, "SELECT record_id FROM records")$record_id
  expect_setequal(after, saved$record_id)
})
