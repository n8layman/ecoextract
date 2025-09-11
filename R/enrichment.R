#' Publication Metadata Enrichment Functions
#' 
#' Enrich publication metadata using CrossRef API

#' Enrich publication metadata using CrossRef
#' @param doi DOI to lookup
#' @param title Publication title (used if DOI not available)
#' @param authors Author names (used if DOI not available)
#' @return List with enriched metadata
#' @export
enrich_publication_metadata <- function(doi = NULL, title = NULL, authors = NULL) {
  if (!requireNamespace("rcrossref", quietly = TRUE)) {
    warning("rcrossref package not available for metadata enrichment")
    return(list(
      success = FALSE,
      metadata = list(),
      message = "rcrossref package not installed"
    ))
  }
  
  tryCatch({
    if (!is.null(doi) && doi != "" && doi != "null") {
      # Direct DOI lookup
      cat("Looking up DOI:", doi, "\n")
      result <- rcrossref::cr_works(doi = doi)
      
      if (length(result$data) > 0) {
        work <- result$data
        return(list(
          success = TRUE,
          metadata = list(
            title = work$title[1] %||% NULL,
            doi = work$DOI[1] %||% doi,
            journal = work$container.title[1] %||% NULL,
            publication_year = extract_year_from_crossref(work$published.print[1] %||% work$published.online[1]),
            all_authors = extract_authors_from_crossref(work$author[[1]]),
            first_author_lastname = extract_first_author_lastname(work$author[[1]])
          ),
          message = "Successfully enriched via DOI"
        ))
      }
    }
    
    if (!is.null(title) && title != "" && !is.null(authors) && authors != "") {
      # Title + author search
      cat("Searching by title and author:", title, "by", authors, "\n")
      result <- rcrossref::cr_works(query = paste(title, authors), limit = 5)
      
      if (length(result$data) > 0) {
        # Take best match (first result)
        work <- result$data[1, ]
        return(list(
          success = TRUE,
          metadata = list(
            title = work$title[1] %||% title,
            doi = work$DOI[1] %||% NULL,
            journal = work$container.title[1] %||% NULL,
            publication_year = extract_year_from_crossref(work$published.print[1] %||% work$published.online[1]),
            all_authors = extract_authors_from_crossref(work$author[[1]]),
            first_author_lastname = extract_first_author_lastname(work$author[[1]])
          ),
          message = "Successfully enriched via title/author search"
        ))
      }
    }
    
    # No enrichment possible
    return(list(
      success = FALSE,
      metadata = list(),
      message = "No DOI or title/author provided for enrichment"
    ))
    
  }, error = function(e) {
    return(list(
      success = FALSE,
      metadata = list(),
      message = paste("CrossRef lookup failed:", e$message)
    ))
  })
}

#' Extract publication year from CrossRef date
#' @param crossref_date Date from CrossRef API
#' @return Numeric year or NULL
extract_year_from_crossref <- function(crossref_date) {
  if (is.null(crossref_date) || length(crossref_date) == 0) {
    return(NULL)
  }
  
  tryCatch({
    # CrossRef dates are often in format list(c(year, month, day))
    if (is.list(crossref_date) && length(crossref_date) > 0) {
      year_part <- crossref_date[[1]]
      if (is.numeric(year_part) && length(year_part) > 0) {
        return(as.numeric(year_part[1]))
      }
    }
    
    # Try parsing as string
    if (is.character(crossref_date)) {
      year_match <- regexpr("\\d{4}", crossref_date)
      if (year_match > 0) {
        return(as.numeric(regmatches(crossref_date, year_match)))
      }
    }
    
    return(NULL)
  }, error = function(e) {
    return(NULL)
  })
}

#' Extract authors array from CrossRef author data
#' @param crossref_authors Author data from CrossRef
#' @return JSON string of author array
extract_authors_from_crossref <- function(crossref_authors) {
  if (is.null(crossref_authors) || length(crossref_authors) == 0) {
    return("[]")
  }
  
  tryCatch({
    author_list <- list()
    
    for (i in 1:nrow(crossref_authors)) {
      author <- crossref_authors[i, ]
      
      # Build author name
      given <- author$given %||% ""
      family <- author$family %||% ""
      
      if (given != "" && family != "") {
        full_name <- paste(given, family)
      } else if (family != "") {
        full_name <- family
      } else if (given != "") {
        full_name <- given
      } else {
        full_name <- "Unknown Author"
      }
      
      author_list[[i]] <- list(
        given = given,
        family = family,
        full_name = full_name
      )
    }
    
    return(jsonlite::toJSON(author_list, auto_unbox = TRUE))
    
  }, error = function(e) {
    return("[]")
  })
}

#' Extract first author lastname from CrossRef data
#' @param crossref_authors Author data from CrossRef
#' @return Character string of first author lastname
extract_first_author_lastname <- function(crossref_authors) {
  if (is.null(crossref_authors) || nrow(crossref_authors) == 0) {
    return("Author")
  }
  
  tryCatch({
    first_author <- crossref_authors[1, ]
    lastname <- first_author$family %||% first_author$given %||% "Author"
    
    # Clean lastname for occurrence ID generation
    clean_lastname <- stringr::str_replace_all(lastname, "[^A-Za-z]", "")
    if (nchar(clean_lastname) == 0) {
      return("Author")
    }
    
    return(clean_lastname)
    
  }, error = function(e) {
    return("Author")
  })
}

#' Simple null coalescing operator
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (is.character(x) && x == "")) y else x
}