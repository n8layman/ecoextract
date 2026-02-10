# Deduplication Unit Tests
# Local tests only -- no API keys required

test_that("canonicalize normalizes text correctly", {
  # Unicode normalization
  expect_equal(canonicalize("café"), "café")

  # Lowercase
  expect_equal(canonicalize("Myotis lucifugus"), "myotis lucifugus")

  # Trim whitespace
  expect_equal(canonicalize("  bat  "), "bat")

  # Combined
  expect_equal(canonicalize("  Myotis LUCIFUGUS  "), "myotis lucifugus")

  # Handles NULL and NA
  expect_equal(canonicalize(NULL), NULL)
  expect_equal(canonicalize(NA_character_), NA_character_)
})


test_that("cosine_similarity calculates correctly", {
  # Identical vectors
  vec1 <- c(1, 0, 0)
  expect_equal(cosine_similarity(vec1, vec1), 1.0)

  # Orthogonal vectors
  vec2 <- c(0, 1, 0)
  expect_equal(cosine_similarity(vec1, vec2), 0.0)

  # Opposite vectors
  vec3 <- c(-1, 0, 0)
  expect_equal(cosine_similarity(vec1, vec3), -1.0)

  # Similar vectors
  vec4 <- c(1, 0.1, 0)
  similarity <- cosine_similarity(vec1, vec4)
  expect_true(similarity > 0.9 && similarity < 1.0)

  # Different length vectors should error
  vec5 <- c(1, 0)
  expect_error(cosine_similarity(vec1, vec5), "same length")

  # Zero vectors
  vec_zero <- c(0, 0, 0)
  expect_equal(cosine_similarity(vec_zero, vec1), 0)
})

test_that("jaccard_similarity calculates correctly", {
  # Identical strings
  expect_equal(jaccard_similarity("myotis lucifugus", "myotis lucifugus"), 1.0)

  # Completely different strings
  expect_true(jaccard_similarity("bat", "mouse") < 0.5)

  # Similar strings (single char typo) - with trigrams this gives ~0.75
  sim <- jaccard_similarity("myotis lucifugus", "myotis lucifugis")
  expect_true(sim > 0.7 && sim < 0.9)

  # Different case (should be canonicalized to identical)
  expect_equal(jaccard_similarity("Myotis Lucifugus", "myotis lucifugus"), 1.0)

  # Partial overlap (same genus, different species)
  sim2 <- jaccard_similarity("myotis lucifugus", "myotis yumanensis")
  expect_true(sim2 > 0.2 && sim2 < 0.4)

  # Empty strings
  expect_equal(jaccard_similarity("", ""), 1.0)
  expect_equal(jaccard_similarity("bat", ""), 0.0)

  # NA values
  expect_equal(jaccard_similarity(NA_character_, "bat"), 0.0)
  expect_equal(jaccard_similarity("bat", NA_character_), 0.0)

  # Very short strings (shorter than n-gram size)
  expect_equal(jaccard_similarity("ab", "ab"), 1.0)
  expect_equal(jaccard_similarity("ab", "cd"), 0.0)
})

test_that("deduplicate_records with no existing records returns all new records", {
  new_records <- tibble::tibble(
    bat_species_scientific_name = c("Myotis lucifugus", "Eptesicus fuscus"),
    interacting_organism_scientific_name = c("Pseudogymnoascus destructans", "Corynorhinus townsendii")
  )

  existing_records <- tibble::tibble()

  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("bat_species_scientific_name", "interacting_organism_scientific_name")
        )
      )
    )
  )

  result <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list
  )

  expect_equal(nrow(result$unique_records), 2)
  expect_equal(result$duplicates_found, 0)
  expect_equal(result$new_records_count, 2)
})

test_that("deduplicate_records errors when x-unique-fields is missing", {
  new_records <- tibble::tibble(
    bat_species_scientific_name = c("Myotis lucifugus")
  )

  existing_records <- tibble::tibble(
    bat_species_scientific_name = c("Myotis lucifugus")
  )

  # Schema with no x-unique-fields
  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          properties = list(
            bat_species_scientific_name = list(type = "string")
          )
        )
      )
    )
  )

  expect_error(
    deduplicate_records(
      new_records = new_records,
      existing_records = existing_records,
      schema_list = schema_list
    ),
    "Schema must define 'x-unique-fields'"
  )
})

test_that("deduplicate_records validates x-unique-fields against schema properties", {
  new_records <- tibble::tibble(
    bat_species_scientific_name = c("Myotis lucifugus")
  )

  existing_records <- tibble::tibble()

  # Schema with invalid field in x-unique-fields
  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("bat_species_scientific_name", "nonexistent_field"),
          properties = list(
            bat_species_scientific_name = list(type = "string")
          )
        )
      )
    )
  )

  expect_error(
    deduplicate_records(
      new_records = new_records,
      existing_records = existing_records,
      schema_list = schema_list
    ),
    "Invalid x-unique-fields in schema: nonexistent_field"
  )
})

# Jaccard method tests (no API needed) -----------------------------------------

test_that("jaccard method: detects exact duplicates", {
  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("species", "location"),
          properties = list(
            species = list(type = "string"),
            location = list(type = "string")
          )
        )
      )
    )
  )

  existing_records <- tibble::tibble(
    species = c("Myotis lucifugus", "Eptesicus fuscus"),
    location = c("Cave A", "Cave B")
  )

  new_records <- tibble::tibble(
    species = c("Myotis lucifugus", "Lasiurus borealis"),
    location = c("Cave A", "Cave C")
  )

  result <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list,
    min_similarity = 0.95,
    similarity_method = "jaccard"
  )

  # First record is exact duplicate, second is unique
  expect_equal(result$duplicates_found, 1)
  expect_equal(nrow(result$unique_records), 1)
  expect_equal(result$unique_records$species[1], "Lasiurus borealis")
})

test_that("jaccard method: handles typos with lower threshold", {
  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("species"),
          properties = list(
            species = list(type = "string")
          )
        )
      )
    )
  )

  existing_records <- tibble::tibble(
    species = "Myotis lucifugus"
  )

  # Typo: lucifugis instead of lucifugus (single char diff = ~0.75 similarity)
  new_records <- tibble::tibble(
    species = "Myotis lucifugis"
  )

  result <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list,
    min_similarity = 0.70,  # Lower threshold to catch typos (trigram gives ~0.75)
    similarity_method = "jaccard"
  )

  # Should catch the typo as duplicate
  expect_equal(result$duplicates_found, 1)
  expect_equal(nrow(result$unique_records), 0)
})

test_that("jaccard method: partial field match does not create duplicate", {
  schema_list <- list(
    properties = list(
      records = list(
        items = list(
          "x-unique-fields" = c("pathogen", "host"),
          properties = list(
            pathogen = list(type = "string"),
            host = list(type = "string")
          )
        )
      )
    )
  )

  existing_records <- tibble::tibble(
    pathogen = "Borrelia burgdorferi",
    host = "Peromyscus leucopus"
  )

  # Same pathogen, different host
  new_records <- tibble::tibble(
    pathogen = "Borrelia burgdorferi",
    host = "Myotis lucifugus"
  )

  result <- deduplicate_records(
    new_records = new_records,
    existing_records = existing_records,
    schema_list = schema_list,
    min_similarity = 0.95,
    similarity_method = "jaccard"
  )

  # ALL fields must match - should be unique
  expect_equal(result$duplicates_found, 0)
  expect_equal(nrow(result$unique_records), 1)
})
