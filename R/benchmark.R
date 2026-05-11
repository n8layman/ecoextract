#' Duplicate a template database for benchmark trials
#'
#' Creates N copies of a template database, preserving pipeline state up to
#' a specified stage. This avoids re-running expensive deterministic steps
#' (like OCR) across benchmark trials.
#'
#' @param template_db Path to the template SQLite database
#' @param n Number of trial copies to create
#' @param through Pipeline stage to preserve. One of:
#'   \describe{
#'     \item{"ocr"}{Keep OCR results. Trials re-run metadata, extraction, and refinement.}
#'     \item{"metadata"}{Keep OCR + metadata. Trials re-run extraction and refinement.}
#'     \item{"extraction"}{Keep OCR + metadata + extraction. Trials only re-run refinement.}
#'   }
#' @param pattern Naming pattern for trial databases. Use \code{{n}} for the
#'   trial number (glue syntax). Default: \code{"{basename}_trial_{n}.{ext}"}
#'   where basename and ext come from the template filename.
#' @param dir Output directory for trial databases (default: same directory as template)
#' @return Character vector of paths to the created trial databases
#' @keywords internal
#' @export
#'
#' @examples
#' \dontrun{
#' # Create 10 trial copies preserving OCR
#' trial_dbs <- duplicate_for_trials("template.db", n = 10, through = "ocr")
#'
#' # Custom naming pattern
#' trial_dbs <- duplicate_for_trials("template.db", n = 5, pattern = "benchmark_trial_{n}.sqlite")
#'
#' # Run pipeline on each trial (OCR auto-skips)
#' results <- purrr::map(trial_dbs, \(db) {
#'   process_documents("pdfs/", db_conn = db)
#' })
#' }
duplicate_for_trials <- function(template_db,
                                 n,
                                 through = c("ocr", "metadata", "extraction"),
                                 pattern = NULL,
                                 dir = NULL) {
  through <- match.arg(through)

  if (!file.exists(template_db)) {
    stop("Template database not found: ", template_db)
  }
  if (!is.numeric(n) || length(n) != 1 || n < 1) {
    stop("n must be a positive integer")
  }
  n <- as.integer(n)

  if (is.null(dir)) {
    dir <- dirname(template_db)
  }
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE)
  }

  # Generate trial paths
  basename <- tools::file_path_sans_ext(basename(template_db))
  ext <- tools::file_ext(template_db)
  if (nchar(ext) == 0) ext <- "db"

  if (is.null(pattern)) {
    pattern <- "{basename}_trial_{n}.{ext}"
  }

  trial_paths <- purrr::map_chr(seq_len(n), function(n) {
    file.path(dir, glue::glue(pattern))
  })

  existing <- trial_paths[file.exists(trial_paths)]
  if (length(existing) > 0) {
    stop(
      "Trial databases already exist (use unlink() to remove first):\n",
      paste0("  ", existing, collapse = "\n")
    )
  }

  # Copy and scrub each trial
  purrr::walk(trial_paths, function(path) {
    file.copy(template_db, path)
    scrub_pipeline_stages(path, through)
  })

  message("Created ", n, " trial databases from ", basename(template_db),
          " (through: ", through, ")")

  trial_paths
}

#' Scrub pipeline stages beyond a cutoff from a database
#'
#' @param db_path Path to SQLite database to modify in place
#' @param through Pipeline stage to preserve ("ocr", "metadata", "extraction")
#' @return NULL (modifies database in place)
#' @keywords internal
scrub_pipeline_stages <- function(db_path, through) {
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  configure_sqlite_connection(con)
  withr::defer(DBI::dbDisconnect(con))

  if (through == "ocr") {
    DBI::dbExecute(con, "
      UPDATE documents SET
        title = NULL, first_author_lastname = NULL, authors = NULL,
        publication_year = NULL, doi = NULL, journal = NULL,
        volume = NULL, issue = NULL, pages = NULL, issn = NULL,
        publisher = NULL, bibliography = NULL, language = NULL,
        metadata_status = NULL, metadata_llm_model = NULL, metadata_log = NULL
    ")
  }

  if (through %in% c("ocr", "metadata")) {
    DBI::dbExecute(con, "
      UPDATE documents SET
        extraction_reasoning = NULL, records_extracted = NULL,
        extraction_status = NULL, extraction_llm_model = NULL, extraction_log = NULL
    ")
    DBI::dbExecute(con, "DELETE FROM records")
    DBI::dbExecute(con, "DELETE FROM record_edits")
  }

  # Refinement is always cleared (all levels are "at most through extraction")
  DBI::dbExecute(con, "
    UPDATE documents SET
      refinement_reasoning = NULL, refinement_status = NULL,
      refinement_llm_model = NULL, refinement_log = NULL
  ")

  # Benchmarks should not inherit human review state
  DBI::dbExecute(con, "UPDATE documents SET reviewed_at = NULL")

  invisible(NULL)
}
