# PLANT-POLLINATOR INTERACTION EXTRACTION

Extract all plant-pollinator interaction records from the provided scientific document.

## What to Extract

Extract records of:
- **Direct observations** of pollinators visiting flowers
- **Experimental pollination studies** showing effectiveness
- **Pollen transfer observations** between plant and pollinator
- **Floral visitor surveys** documenting pollinator species

## Extraction Rules

### Record Identification
- Each unique plant-pollinator pair = one record
- If multiple observations of same pair at different times/locations = separate records
- If study mentions "common pollinators" without species names, extract as much detail as available

### Organism Identification
- `organisms_identifiable`: Set to "true" only if BOTH plant and pollinator are identified to species level
- Extract scientific names when available (e.g., "Bombus impatiens", "Asclepias syriaca")
- Extract common names when available (e.g., "common eastern bumble bee", "common milkweed")
- If only genus or family given, still extract but set `organisms_identifiable` to "false"

### Supporting Evidence
- **VERBATIM QUOTES ONLY** - copy sentences exactly as written in source
- Include sentences that:
  - Describe the pollination observation
  - Identify the plant species
  - Identify the pollinator species
  - Provide location/date context
  - Describe pollination effectiveness or behavior
- **One complete sentence per array element**
- If evidence references tables/figures, include the table caption

### Location and Dates
- Extract specific locations when mentioned (e.g., "Rocky Mountain Biological Laboratory, Colorado")
- Use format YYYY-MM-DD for dates when possible
- If only year or season given, extract what's available

### Page Numbers
- Record the page number where the observation is first described

## What NOT to Extract

- ❌ Plants that are wind-pollinated with no animal visitors mentioned
- ❌ Mentions of pollination without specific plant-pollinator pairs
- ❌ General statements about pollination biology without data
- ❌ Hypothetical or predicted pollinator relationships not observed

## Output Format

Return JSON with a "records" array containing all extracted plant-pollinator interaction records following the schema structure.

## Quality Standards

- Prefer specificity over completeness (better to have partial data for real observations than invented complete data)
- Always include page numbers for verification
- Include at least one supporting sentence per record
- Flag unclear or uncertain records rather than omitting them
