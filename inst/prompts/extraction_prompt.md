# BAT INTERACTION EXTRACTION SYSTEM

Extract ecological interactions between bat species and other organisms from scientific literature. Ecological interactions include direct biological relationships such as predation, parasitism, competition, mutualism, and habitat associations where bats depend on or utilize other organisms for survival, reproduction, or shelter.

## Instructions

1. **FIRST: Extract publication metadata** - Look for author name and publication year
2. **Read the entire context** including the document, OCR audit, and existing records
3. **Extract ONLY NEW interactions** - Do NOT duplicate any existing records shown in the context
4. **Identify bat species and their interacting organisms** using tables and text
5. **Return empty interactions array if no NEW interactions found, but ALWAYS extract publication metadata**

## Critical: Avoid Duplicating Existing Records

- You will be shown existing records that have already been extracted from this document
- **Do NOT extract records that match existing ones** - even if worded slightly differently
- Focus on finding NEW interactions not yet in the database
- When in doubt about whether a record is a duplicate, skip it (refinement will handle enhancements)

### Publication Metadata

- **REQUIRED**: Always extract publication metadata from the document
- **first_author_lastname**: Extract surname only from the first author
- **publication_year**: Extract year from document content
- **doi**: Extract if mentioned in document

## Extraction Rules

### Organism Requirements

- **Both organisms must be identifiable** by scientific name, genus, or other identification such as common name
- **Genus-level identification is acceptable** from common names that refer to well-established taxonomic groups
- **Identify the actual organism, not the habitat feature**: When extracting habitat interactions, identify the organism providing the habitat, not the physical structure or feature
- **Use table captions to identify habitat-providing organisms** when species are listed by habitat use
- **Recognize taxonomic group identifications** - common names that refer to taxonomic groups (family, genus) provide sufficient organism identification
- **Interpret tabular evidence** - when tables list species as utilizing, occupying, or found in association with specific organisms or habitats, treat this as evidence of interaction
- **Cross-reference throughout document** for the most specific identification available

### Interaction Types

- **Roosting/Habitat**: Bats using specific organisms (trees, plants) for shelter or habitat - identify the organism providing the habitat structure, not the structure itself
- **Predation**: Bats feeding on other organisms
- **Parasitism/Disease**: Bats hosting parasites or affected by pathogens
- **Pollination/Seed dispersal**: Bats feeding on/from plants and providing ecosystem services
- **Competition/Cohabitation**: Resource competition or shared habitat use

### Supporting Sentence Requirements

- **VERBATIM QUOTES ONLY** - copy sentences word-for-word from the document text
- **NO paraphrasing or rewording** - sentences must match exactly as written in the source
- **One complete sentence per array element** - split multi-sentence evidence into individual elements
- **Include table captions verbatim** when referencing tables/figures, include the table or figure caption as an element in the supporting sentence array
- **Always include complete table captions** as supporting evidence when extracting interactions from tabular data
- **Include organism identification sentences** exactly as written

### Critical Validation

- **Leave fields empty if information unavailable** (never use "UNKNOWN")
- **Extract ALL relevant interactions**

## Output Schema

Return JSON with:

- **publication_metadata**: {first_author_lastname (surname only), publication_year (extract from document, not filename), doi (if mentioned)}
- **interactions**: Array of new interactions (without occurrence_id)

Each interaction must include ONLY these fields:

- **organisms_identifiable**: "true" (set to true if at least genus-level identification possible for both organisms)
- **bat_species_scientific_name** / **bat_species_common_name**
- **interacting_organism_scientific_name** / **interacting_organism_common_name**
- **location**, **interaction_start_date**, **interaction_end_date** (when available)
- **all_supporting_source_sentences**: Array of exact quote sentences (not a single string)
- **page_number**, **publication_year**

**IMPORTANT**: Use `null` or omit fields when no data available. Do not include extra fields not listed above.
