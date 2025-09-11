# BAT INTERACTION REFINEMENT SYSTEM

Enhance and improve existing ecological interaction data between bat species and other organisms.

## Refinement Rules

### Enhancement Goals
- **Fill missing organism names** using document tables and cross-references
- **Add missing location/date information** when available in document
- **Improve supporting evidence** by adding complete table captions when referenced
- **Split multi-sentence evidence** into individual array elements
- **Cross-reference with OCR audit tables** for better organism identifications

### Critical Validation Override
- **MUST return ALL existing interactions** even if some have missing data
- **Do NOT apply strict validation** - work with what exists and improve incrementally
- **NEVER delete interactions** that don't meet full identification criteria
- **Preserve all human-edited fields** marked as such in audit context

### Supporting Evidence Enhancement  
- **VERBATIM QUOTES ONLY** - all sentences must match the source document exactly word-for-word
- **NO paraphrasing or synthesis** - copy sentences exactly as written in the document
- **One complete sentence per array element** - split multi-sentence evidence into separate elements
- **MANDATORY: Add complete table captions** when ANY supporting sentence references tables (e.g., "see Table 2", "Table 1 shows"). The full table caption with "TABLE X: [caption text]" must be included as a separate array element.
- **Include organism identification sentences** exactly as written in the source

## Output Schema

Return JSON with:
- **interactions**: Array of ALL refined interactions (with occurrence_ids preserved)
- **validation_flags**: Array of interactions that need human review

Each interaction must include:
- **id**: REQUIRED - preserve exact original database ID (do not change)
- **occurrence_id**: REQUIRED - preserve exact original ID  
- **document_id**: REQUIRED - preserve original document ID
- **organisms_identifiable**: "true" for existing interactions
- **bat_species_scientific_name** / **bat_species_common_name**
- **interacting_organism_scientific_name** / **interacting_organism_common_name**
- **location**, **interaction_start_date**, **interaction_end_date** (enhance when possible)
- **all_supporting_source_sentences**: Enhanced array with individual sentences
- **page_number**, **publication_year**
- **flagged_for_review**: BOOLEAN - true if interaction needs human review
- **review_reason**: STRING - explanation if flagged (e.g., "Vague organism identification", "Insufficient evidence", "Potential duplicate")

## Instructions

1. **Return ALL existing interactions** with their original occurrence_ids and database IDs
2. **Enhance missing data** using document content and OCR audit tables
3. **Improve supporting evidence** by splitting sentences and adding table captions
4. **Cross-reference with tables** to find better organism identifications
5. **Preserve human-edited fields** as noted in audit context
6. **Flag for human review** when interactions have quality issues

## Flagging Criteria

Flag interactions (set `flagged_for_review: true`) when they have:
- **Vague organism identification**: Generic terms like "bats", "insects" without specific species
- **Insufficient evidence**: Missing or very weak supporting sentences
- **Schema violations**: Missing required fields or invalid data formats
- **Potential duplicates**: Very similar interactions that might be redundant
- **Unclear interactions**: Ambiguous or confusing interaction descriptions
- **Data quality issues**: Conflicting information or obvious errors

**Do NOT flag** interactions just because they're incomplete - only flag clear quality problems that need human attention.

Focus on incremental improvement while maintaining data integrity.