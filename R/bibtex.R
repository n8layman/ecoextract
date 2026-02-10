#' Export Bibliography to BibTeX Format
#'
#' Converts bibliography entries from the database to BibTeX format for use
#' with LaTeX and reference managers. Can export either document metadata
#' (the papers themselves) or extracted citations (references from those papers).
#'
#' @param db_conn Database connection or path to SQLite database file
#' @param document_ids Optional vector of document IDs to export (default: all documents)
#' @param filename Optional output file path (e.g., "references.bib"). If NULL,
#'   returns BibTeX string without writing to file.
#' @param source What to export: "documents" exports metadata for the papers
#'   themselves, "citations" exports the references extracted from those papers
#'   (stored in bibliography field). Default: "documents".
#' @return Character string containing BibTeX entries (invisibly if filename provided)
#' @export
#' @examples
#' \dontrun{
#' # Export document metadata (the papers themselves)
#' export_bibtex(db_conn = "records.db", filename = "papers.bib")
#'
#' # Export extracted citations from papers
#' export_bibtex(db_conn = "records.db", source = "citations",
#'               filename = "citations.bib")
#'
#' # Export citations from specific documents
#' export_bibtex(db_conn = "records.db", document_ids = c(1, 5, 10),
#'               source = "citations")
#'
#' # Get BibTeX as string
#' bib_text <- export_bibtex(db_conn = "records.db")
#' cat(bib_text)
#' }
export_bibtex <- function(db_conn, document_ids = NULL, filename = NULL,
                          source = c("documents", "citations")) {
  source <- match.arg(source)
  # Handle database connection
  if (inherits(db_conn, "DBIConnection")) {
    con <- db_conn
    close_on_exit <- FALSE
  } else {
    if (!file.exists(db_conn)) {
      stop("Database file not found: ", db_conn)
    }
    con <- DBI::dbConnect(RSQLite::SQLite(), db_conn)
    configure_sqlite_connection(con)
    close_on_exit <- TRUE
  }

  if (close_on_exit) {
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }

  # Handle different export sources
  if (source == "citations") {
    return(export_citations_bibtex(con, document_ids, filename))
  }

  # Build query with optional document filtering (for documents source)
  if (!is.null(document_ids) && length(document_ids) > 0) {
    placeholders <- paste(rep("?", length(document_ids)), collapse = ", ")
    query <- paste0(
      "SELECT document_id, first_author_lastname, authors, title, journal, ",
      "publication_year, volume, issue, pages, doi, publisher, issn ",
      "FROM documents WHERE document_id IN (", placeholders, ")"
    )
    docs <- DBI::dbGetQuery(con, query, params = as.list(document_ids))
  } else {
    query <- paste0(
      "SELECT document_id, first_author_lastname, authors, title, journal, ",
      "publication_year, volume, issue, pages, doi, publisher, issn ",
      "FROM documents"
    )
    docs <- DBI::dbGetQuery(con, query)
  }

  if (nrow(docs) == 0) {
    message("No documents found")
    return(invisible(""))
  }

  # Convert each document to BibTeX entry
  bibtex_entries <- vapply(seq_len(nrow(docs)), function(i) {
    doc <- docs[i, ]

    # Generate citation key: LastName + Year (e.g., "Smith2023")
    author_key <- if (!is.na(doc$first_author_lastname) && doc$first_author_lastname != "") {
      # Remove spaces and special characters
      gsub("[^A-Za-z0-9]", "", doc$first_author_lastname)
    } else {
      paste0("Doc", doc$document_id)
    }

    year_key <- if (!is.na(doc$publication_year)) {
      as.character(doc$publication_year)
    } else {
      "NODATE"
    }

    citation_key <- paste0(author_key, year_key)

    # Determine entry type (default to @article for journals)
    entry_type <- if (!is.na(doc$journal) && doc$journal != "") {
      "article"
    } else {
      "misc"
    }

    # Build fields list
    fields <- character()

    # Author - required for most entry types
    if (!is.na(doc$authors) && doc$authors != "") {
      # Parse JSON array if it's JSON, otherwise use as-is
      author_text <- tryCatch({
        authors_list <- jsonlite::fromJSON(doc$authors)
        if (is.character(authors_list) && length(authors_list) > 1) {
          paste(authors_list, collapse = " and ")
        } else {
          doc$authors
        }
      }, error = function(e) {
        doc$authors
      })
      fields <- c(fields, sprintf("  author = {%s}", author_text))
    }

    # Title - required
    if (!is.na(doc$title) && doc$title != "") {
      fields <- c(fields, sprintf("  title = {%s}", doc$title))
    }

    # Journal - required for @article
    if (!is.na(doc$journal) && doc$journal != "") {
      fields <- c(fields, sprintf("  journal = {%s}", doc$journal))
    }

    # Year - required for most entry types
    if (!is.na(doc$publication_year)) {
      fields <- c(fields, sprintf("  year = {%s}", doc$publication_year))
    }

    # Optional fields
    if (!is.na(doc$volume) && doc$volume != "") {
      fields <- c(fields, sprintf("  volume = {%s}", doc$volume))
    }

    if (!is.na(doc$issue) && doc$issue != "") {
      fields <- c(fields, sprintf("  number = {%s}", doc$issue))
    }

    if (!is.na(doc$pages) && doc$pages != "") {
      fields <- c(fields, sprintf("  pages = {%s}", doc$pages))
    }

    if (!is.na(doc$doi) && doc$doi != "") {
      fields <- c(fields, sprintf("  doi = {%s}", doc$doi))
    }

    if (!is.na(doc$publisher) && doc$publisher != "") {
      fields <- c(fields, sprintf("  publisher = {%s}", doc$publisher))
    }

    if (!is.na(doc$issn) && doc$issn != "") {
      fields <- c(fields, sprintf("  issn = {%s}", doc$issn))
    }

    # Format BibTeX entry
    if (length(fields) > 0) {
      paste0("@", entry_type, "{", citation_key, ",\n",
             paste(fields, collapse = ",\n"), "\n}")
    } else {
      # Empty entry if no fields
      paste0("@", entry_type, "{", citation_key, "\n}")
    }
  }, character(1))

  # Handle duplicate citation keys
  bibtex_entries <- make_unique_keys(bibtex_entries)

  # Combine all entries
  result <- paste(bibtex_entries, collapse = "\n\n")

  # Write to file if requested
  if (!is.null(filename)) {
    writeLines(result, filename)
    message("Exported ", nrow(docs), " BibTeX entries to ", filename)
    return(invisible(result))
  }

  return(result)
}

#' Make Citation Keys Unique
#'
#' Handles duplicate citation keys by appending letters (a, b, c, etc.)
#'
#' @param bibtex_entries Character vector of BibTeX entries
#' @return Character vector with unique citation keys
#' @keywords internal
make_unique_keys <- function(bibtex_entries) {
  # Extract citation keys from entries
  keys <- vapply(bibtex_entries, function(entry) {
    # Match pattern: @type{key,
    match <- regmatches(entry, regexpr("@[a-z]+\\{[^,]+", entry))
    if (length(match) > 0) {
      # Extract just the key part
      sub("@[a-z]+\\{", "", match)
    } else {
      ""
    }
  }, character(1))

  # Find duplicates
  key_counts <- table(keys)
  duplicates <- names(key_counts[key_counts > 1])

  if (length(duplicates) == 0) {
    return(bibtex_entries)
  }

  # Add suffixes to duplicates
  for (dup_key in duplicates) {
    indices <- which(keys == dup_key)
    suffixes <- letters[seq_along(indices)]

    for (i in seq_along(indices)) {
      idx <- indices[i]
      new_key <- paste0(dup_key, suffixes[i])
      # Replace the key in the entry
      bibtex_entries[idx] <- sub(
        paste0("\\{", dup_key, ","),
        paste0("{", new_key, ","),
        bibtex_entries[idx]
      )
    }
  }

  return(bibtex_entries)
}

#' Export Citations from Bibliography Field
#'
#' Exports citations extracted from papers (stored in bibliography column)
#' to BibTeX format.
#'
#' @param con Database connection object
#' @param document_ids Optional vector of document IDs
#' @param filename Optional output file path
#' @return Character string containing BibTeX entries
#' @keywords internal
export_citations_bibtex <- function(con, document_ids = NULL, filename = NULL) {
  # Build query with optional document filtering
  if (!is.null(document_ids) && length(document_ids) > 0) {
    placeholders <- paste(rep("?", length(document_ids)), collapse = ", ")
    query <- paste0(
      "SELECT document_id, first_author_lastname, publication_year, bibliography ",
      "FROM documents WHERE document_id IN (", placeholders, ") ",
      "AND bibliography IS NOT NULL AND bibliography != ''"
    )
    docs <- DBI::dbGetQuery(con, query, params = as.list(document_ids))
  } else {
    query <- paste0(
      "SELECT document_id, first_author_lastname, publication_year, bibliography ",
      "FROM documents WHERE bibliography IS NOT NULL AND bibliography != ''"
    )
    docs <- DBI::dbGetQuery(con, query)
  }

  if (nrow(docs) == 0) {
    message("No documents with bibliography citations found")
    return(invisible(""))
  }

  # Parse citations from each document
  all_citations <- list()
  citation_counter <- 1

  for (i in seq_len(nrow(docs))) {
    doc <- docs[i, ]

    # Parse JSON array of citations
    citations <- tryCatch({
      jsonlite::fromJSON(doc$bibliography)
    }, error = function(e) {
      message("Warning: Could not parse bibliography for document ", doc$document_id)
      character(0)
    })

    if (length(citations) == 0) next

    # Generate BibTeX entries for each citation
    for (j in seq_along(citations)) {
      citation_text <- citations[j]

      # Generate citation key based on source document
      author_key <- if (!is.na(doc$first_author_lastname) && doc$first_author_lastname != "") {
        gsub("[^A-Za-z0-9]", "", doc$first_author_lastname)
      } else {
        paste0("Doc", doc$document_id)
      }

      year_key <- if (!is.na(doc$publication_year)) {
        as.character(doc$publication_year)
      } else {
        "NODATE"
      }

      # Create unique key: SourceAuthorYear_citN
      citation_key <- paste0(author_key, year_key, "_cit", j)

      # Parse citation text to extract fields (heuristic approach)
      parsed <- parse_citation_text(citation_text)

      # Build BibTeX entry
      entry_type <- parsed$type %||% "misc"
      fields <- character()

      if (!is.null(parsed$author) && parsed$author != "") {
        fields <- c(fields, sprintf("  author = {%s}", parsed$author))
      }

      if (!is.null(parsed$title) && parsed$title != "") {
        fields <- c(fields, sprintf("  title = {%s}", parsed$title))
      }

      if (!is.null(parsed$journal) && parsed$journal != "") {
        fields <- c(fields, sprintf("  journal = {%s}", parsed$journal))
      }

      if (!is.null(parsed$year) && parsed$year != "") {
        fields <- c(fields, sprintf("  year = {%s}", parsed$year))
      }

      if (!is.null(parsed$volume) && parsed$volume != "") {
        fields <- c(fields, sprintf("  volume = {%s}", parsed$volume))
      }

      if (!is.null(parsed$pages) && parsed$pages != "") {
        fields <- c(fields, sprintf("  pages = {%s}", parsed$pages))
      }

      if (!is.null(parsed$doi) && parsed$doi != "") {
        fields <- c(fields, sprintf("  doi = {%s}", parsed$doi))
      }

      # If no structured fields extracted, include raw citation
      if (length(fields) == 0) {
        fields <- c(fields, sprintf("  note = {%s}", citation_text))
      }

      # Format BibTeX entry
      bibtex_entry <- paste0("@", entry_type, "{", citation_key, ",\n",
                            paste(fields, collapse = ",\n"), "\n}")

      all_citations[[citation_counter]] <- bibtex_entry
      citation_counter <- citation_counter + 1
    }
  }

  if (length(all_citations) == 0) {
    message("No citations extracted")
    return(invisible(""))
  }

  # Combine all entries
  result <- paste(unlist(all_citations), collapse = "\n\n")

  # Write to file if requested
  if (!is.null(filename)) {
    writeLines(result, filename)
    message("Exported ", length(all_citations), " citation entries to ", filename)
    return(invisible(result))
  }

  return(result)
}

#' Parse Citation Text to Extract Fields
#'
#' Attempts to extract structured fields from a citation string using
#' heuristic pattern matching.
#'
#' @param citation_text Character string containing citation
#' @return List with extracted fields (author, title, journal, year, etc.)
#' @keywords internal
parse_citation_text <- function(citation_text) {
  result <- list(type = "article")

  # Extract year (4-digit number)
  year_match <- regmatches(citation_text, gregexpr("\\b(19|20)\\d{2}\\b", citation_text))
  if (length(year_match[[1]]) > 0) {
    result$year <- year_match[[1]][1]
  }

  # Extract DOI
  doi_match <- regmatches(citation_text, regexpr("10\\.\\d{4,}/[^\\s]+", citation_text))
  if (length(doi_match) > 0) {
    result$doi <- doi_match
  }

  # Extract volume/pages pattern: Vol(Issue):pages or Vol:pages
  vol_pages <- regmatches(citation_text, regexpr("\\d+\\(\\d+\\):\\d+(-\\d+)?|\\d+:\\d+(-\\d+)?", citation_text))
  if (length(vol_pages) > 0) {
    parts <- strsplit(vol_pages, ":", fixed = TRUE)[[1]]
    if (length(parts) == 2) {
      # Extract volume (remove issue number if present)
      result$volume <- gsub("\\(\\d+\\)", "", parts[1])
      result$pages <- parts[2]
    }
  }

  # Try to extract author (first part before year, up to first period or comma)
  if (!is.null(result$year)) {
    author_pattern <- paste0("^([^.]+).*?", result$year)
    author_match <- regmatches(citation_text, regexpr(author_pattern, citation_text))
    if (length(author_match) > 0) {
      # Clean up: remove year and trailing punctuation
      author_text <- gsub(result$year, "", author_match)
      author_text <- gsub("[.,;]+$", "", author_text)
      author_text <- trimws(author_text)
      if (nchar(author_text) > 0 && nchar(author_text) < 200) {
        result$author <- author_text
      }
    }
  }

  # Title is hard to extract reliably from unstructured text
  # Journal name is also difficult without more context

  return(result)
}
