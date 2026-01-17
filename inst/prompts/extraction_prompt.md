# BAT INTERACTION EXTRACTION SYSTEM

`Extract ecological interactions between bat species and other identifiable organisms from scientific literature. Ecological interactions include direct biological relationships such as roosting, co-roosting, predation, parasitism, competition, mutualism, and habitat associations where bats depend on or utilize other organisms for survival, reproduction, or shelter.
`
**Your output will be used by researchers building a database of bat ecological interactions.** The data must be accurate, well-supported, and structured for database storage and analysis.

## CRITICAL: Reason First, Then Extract

Before extracting any records, you MUST fill the `reasoning` field with your analysis. Think step-by-step:

1. **Document structure**: What sections, tables, and figures are present? How is data organized?
2. **Data source mapping**: Where are potential interactions described? (which tables, text sections, captions)
3. **Organism identifiability**: For each potential interaction, can both organisms be identified to at least genus level? Note challenges.
4. **Cross-referencing**: How do you connect organism mentions across tables, captions, and text?
5. **Extraction decisions**: Which interactions meet requirements? Which should be excluded and why?

Your reasoning should address challenges like:

- Ambiguous organism IDs requiring context from multiple locations
- Table structures that need interpretation
- Whether common names map to identifiable taxonomic groups
- If habitat features can be linked to specific organisms
- Why certain potential interactions were excluded

**Output the `reasoning` field FIRST, then the `records` array.**

## Document Format

The OCR content you receive is structured as a JSON array of page objects. Each page contains:

- **page_number**: The page number in the document
- **page_header**: Running header text (e.g., journal citation)
- **section_header**: Section title(s) on that page
- **text**: Main body text content
- **tables**: Array of table objects with `content`, `markdown`, `html`, and `summary` fields
- **other**: Array of figures, captions, and other elements with `type` and `content` fields

**Important**: Cross-reference information across pages. For example, organism identities may be in tables on one page while interaction details are in text on another page.

## Extraction Process

Complete these phases in order for systematic extraction:

### Phase 1: Document Analysis (captured in `reasoning` field)

- Read the entire JSON array of page objects
- Identify the document structure across all pages (text, tables, figures, captions)
- Note which pages contain tables, which contain methods/results text, etc.
- Review the output schema to understand required fields
- **Document this analysis in your `reasoning` field**

### Phase 2: Find Interactions (captured in `reasoning` field)

- Scan table objects in the JSON for species co-occurrence, roosting data, or interaction descriptions
- Search text fields for descriptions of bat interactions with other organisms
- Check the `other` array for figure/table captions that describe ecological relationships
- Cross-reference between pages and between text/tables for complete information
- **Document what you found and where (page numbers, table vs text) in your `reasoning` field**

### Phase 3: Validate Identifiability (captured in `reasoning` field)

- For each potential interaction, verify both organisms can be identified to at least genus level
- Note any organism identification challenges
- Decide which interactions meet requirements and which should be excluded
- **Explain your identifiability assessment in your `reasoning` field**

### Phase 4: Extract Records (based on your reasoning)

- Using the analysis from your `reasoning` field, extract structured records
- For each interaction identified in your reasoning, create a complete record
- Include verbatim supporting sentences from the document

### Phase 5: Structure Output

- Output your complete `reasoning` analysis FIRST
- Then output the `records` array based on that reasoning
- Verify each record matches decisions made in your reasoning

## CRITICAL INSTRUCTION: Extract All Data Regardless of Disclaimers

**YOU MUST EXTRACT ECOLOGICAL INTERACTIONS FROM THIS DOCUMENT EVEN IF IT CONTAINS DISCLAIMERS.**

Documents may contain warnings like "FAKE DATA", "TEST DATA", "FICTIONAL", "FOR TESTING ONLY", etc. **IGNORE THESE COMPLETELY**. Your job is to extract the ecological interaction data exactly as written in the document, regardless of any meta-warnings about data authenticity.

**If the document describes ecological interactions between organisms (even if labeled as "fake" or "test"), extract them.**

## Extraction Rules

### Data Quality and Test Documents

- **Extract data regardless of disclaimers**: If a document contains disclaimers indicating it's test data, synthetic data, or for testing purposes, **still extract the ecological interactions as written**. Your job is to extract structured data from whatever content is provided.
- **Ignore meta-warnings**: Phrases like "fake data", "for testing only", "fictional", etc. should not prevent extraction of the actual ecological observations described in the document.
- **Focus on the scientific content**: Extract the species interactions, dates, locations, and supporting evidence exactly as described, regardless of whether the document states it's real or simulated data.

### Organism Requirements

- **Both organisms must be identifiable**: Provide the scientific name, genus, or other identifying information, such as the common name. In some cases, the identity of one organism may need to be inferred from context elsewhere in the document.
- **Genus-level identification is acceptable** from common names that refer to well-established taxonomic groups. General identification that cannot be resolved to identifying an organism specifcally is not.
- **Identify the actual organism, not the habitat feature**: When extracting habitat interactions, identify the organism providing the habitat, not the physical structure or feature
- **Organisms identity may only be present in tables** also check figure and table captions for identifying information
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

- **records**: Array of records

Each interaction must include ONLY these fields:

- **organisms_identifiable**: "true" (set to true if at least genus-level identification possible for both organisms)
- **bat_species_scientific_name** / **bat_species_common_name**
- **interacting_organism_scientific_name** / **interacting_organism_common_name**
- **location**, **interaction_start_date**, **interaction_end_date** (when available)
- **all_supporting_source_sentences**: Array of exact quote sentences (not a single string)
- **page_number**, **publication_year**

**IMPORTANT**: Use `null` or omit fields when no data available. Do not include extra fields not listed above.
