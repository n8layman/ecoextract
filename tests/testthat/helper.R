# Helper Functions for Tests
#
# This file contains reusable test utilities and fixtures.
# Helper files are automatically loaded before test files.

# Test Fixtures ----------------------------------------------------------------

#' Create a temporary test database with automatic cleanup
#'
#' Uses withr::local_tempfile() to ensure cleanup happens automatically
#' @param env Environment for cleanup (default: parent.frame())
#' @return Path to temporary SQLite database
local_test_db <- function(env = parent.frame()) {
  db_path <- withr::local_tempfile(fileext = ".sqlite", .local_envir = env)
  init_ecoextract_database(db_path)
  return(db_path)
}

#' Create sample interactions data for testing
#' @return Dataframe with sample interactions
sample_interactions <- function() {
  data.frame(
    bat_species_scientific_name = c("Myotis lucifugus", "Eptesicus fuscus"),
    bat_species_common_name = c("Little Brown Bat", "Big Brown Bat"),
    interacting_organism_scientific_name = c("Corynorhinus townsendii", "Lasiurus cinereus"),
    interacting_organism_common_name = c("Townsend's Big-eared Bat", "Hoary Bat"),
    interaction_type = c("competition", "cohabitation"),
    location = c("Yellowstone National Park", "Grand Canyon"),
    interaction_start_date = c("2020-01-01", "2020-06-15"),
    interaction_end_date = c("2020-12-31", "2020-09-30"),
    all_supporting_source_sentences = c(
      "[\"First sentence.\", \"Second sentence.\"]",
      "[\"Supporting evidence.\"]"
    ),
    page_number = c(5L, 12L),
    publication_year = c(2020L, 2021L),
    stringsAsFactors = FALSE
  )
}

#' Create minimal valid interactions data
#' @return Dataframe with minimal required fields
minimal_interactions <- function() {
  data.frame(
    bat_species_scientific_name = "Myotis lucifugus",
    bat_species_common_name = "Little Brown Bat",
    stringsAsFactors = FALSE
  )
}

#' Create sample publication metadata
#' @return List with publication metadata
sample_publication_metadata <- function() {
  list(
    first_author_lastname = "Smith",
    publication_year = 2020L,
    doi = "10.1234/example.doi"
  )
}

#' Create sample OCR markdown content
#' @return Character string with mock OCR content
sample_ocr_content <- function() {
  "# Bat Ecology Study

## Introduction

This study examines interactions between Myotis lucifugus (Little Brown Bat)
and various organisms in Yellowstone National Park.

## Results

We observed competition between M. lucifugus and Corynorhinus townsendii
(Townsend's Big-eared Bat) for roosting sites.

Table 1: Species interactions observed in 2020.

## References

Smith et al. (2020). Journal of Bat Research. DOI: 10.1234/example.doi
"
}

#' Create sample OCR audit data
#' @return Character string with mock audit JSON
sample_ocr_audit <- function() {
  '{
    "quality_score": 0.95,
    "issues": [],
    "warnings": ["Minor formatting inconsistencies on page 3"]
  }'
}
