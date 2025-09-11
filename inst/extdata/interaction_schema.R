# Interaction Schema Definition - ellmer Structured Output Types
# 
# This file defines the schema for ecological interaction data extraction using
# the ellmer R package for structured LLM outputs.
# 
# ABOUT ELLMER STRUCTURED OUTPUTS:
# ================================
# ellmer provides type-safe structured data extraction from LLMs. Instead of 
# parsing free-form text, you define the exact structure you want using type
# functions, and the LLM returns JSON that gets converted to R objects.
# 
# Key benefits:
# - Guaranteed structure compliance (if LLM follows instructions)
# - Automatic JSON → R conversion (objects → data.frames, arrays → vectors)
# - Type safety with validation
# - Reduces hallucination by constraining outputs
#
# DOCUMENTATION & RESOURCES:
# =========================
# - Main site: https://ellmer.tidyverse.org/
# - Structured data vignette: https://ellmer.tidyverse.org/articles/structured-data.html
# - Getting started: https://ellmer.tidyverse.org/articles/ellmer.html
# - Type reference: https://ellmer.tidyverse.org/reference/Type.html
#
# ELLMER TYPE FUNCTIONS:
# =====================
# - ellmer::type_string(description, required = TRUE)    # Text fields
# - ellmer::type_integer(description, required = TRUE)   # Whole numbers  
# - ellmer::type_number(description, required = TRUE)    # Decimals
# - ellmer::type_boolean(description, required = TRUE)   # True/false
# - ellmer::type_array(description, items = type)        # Lists/vectors
# - ellmer::type_object(description, field1 = type1, ...) # Complex structures
# - ellmer::type_enum(description, values = c(...))      # Constrained choices
#
# SCHEMA DESIGN BEST PRACTICES:
# =============================
# 1. DESCRIPTIVE FIELDS: Write clear, specific descriptions that tell the LLM
#    exactly what data you want and in what format. Be conversational but precise.
#    Good: "Scientific name of the bat species (e.g., Myotis lucifugus)"
#    Bad: "Bat name"
#
# 2. REQUIRED vs OPTIONAL: Use required = FALSE for fields that might not always
#    be available in source documents. This prevents extraction failures.
#    
# 3. DATA TYPES: Match ellmer types to your expected R data types:
#    - Dates/text → type_string  
#    - Page numbers → type_integer
#    - Confidence scores → type_number
#    - Yes/no flags → type_boolean
#
# 4. STRUCTURED OBJECTS: For complex data, build nested structures:
#    type_object("Description", field1 = type_string(...), field2 = type_array(...))
#
# 5. ARRAYS: Use type_array for collections. The 'items' parameter defines what 
#    each array element looks like.
#
# USAGE PATTERN:
# ==============
# This schema gets converted to ellmer objects for LLM extraction:
# 
# type_interaction <- do.call(ellmer::type_object, c(
#   list("Ecological interaction description"),
#   interactions_schema
# ))
# 
# type_interactions <- ellmer::type_array("Array of interactions", items = type_interaction)
# 
# Then used with: claude_chat$extract_data(text, type = type_interactions)
#
# ============================================================================

# Define interaction schema - neutral data structure description
interaction_schema <- list(
  # Core identification
  occurrence_id = ellmer::type_string("Unique interaction identifier", required = FALSE),
  organisms_identifiable = ellmer::type_string("Whether both bat and interacting organism can be identified by scientific name, genus, or specific common name (set to 'true' only when both are identifiable)", required = FALSE),
  
  # Bat information  
  bat_species_scientific_name = ellmer::type_string("Scientific name of bat species", required = FALSE),
  bat_species_common_name = ellmer::type_string("Common name of bat species", required = FALSE),
  
  # Interacting organism
  interacting_organism_scientific_name = ellmer::type_string("Scientific name of interacting organism", required = FALSE),
  interacting_organism_common_name = ellmer::type_string("Common name of interacting organism", required = FALSE),
  
  # Temporal information
  interaction_start_date = ellmer::type_string("Start date of interaction", required = FALSE),
  interaction_end_date = ellmer::type_string("End date of interaction", required = FALSE), 
  
  # Spatial information
  location = ellmer::type_string("Geographic location of interaction", required = FALSE),
  
  # Source information
  all_supporting_source_sentences = ellmer::type_array("Array where each element contains exactly ONE sentence from the source document", items = ellmer::type_string("Individual supporting sentence")),
  page_number = ellmer::type_integer("Page number in document", required = FALSE),
  publication_year = ellmer::type_integer("Year of publication", required = FALSE)
)

# Create type objects for structured output
type_interaction <- do.call(ellmer::type_object, c(
  list("Ecological interaction between identifiable organisms"),
  interaction_schema
))

# Publication metadata schema
publication_metadata_schema <- list(
  first_author_lastname = ellmer::type_string("Last name of first author", required = FALSE),
  publication_year = ellmer::type_integer("Year of publication", required = FALSE),
  doi = ellmer::type_string("DOI if available", required = FALSE)
)

type_publication_metadata <- do.call(ellmer::type_object, c(
  list("Publication metadata"),
  publication_metadata_schema
))

# Complete extraction result schema (used by extraction phase)
type_extraction_result <- ellmer::type_object(
  "Complete extraction result with metadata and interactions",
  publication_metadata = type_publication_metadata,
  interactions = ellmer::type_array("Array of ecological interactions", items = type_interaction)
)

# Refinement result schema (interactions only, no metadata)
type_refinement_result <- ellmer::type_object(
  "Refinement result with enhanced interactions only",
  interactions = ellmer::type_array("Array of refined ecological interactions", items = type_interaction)
)
