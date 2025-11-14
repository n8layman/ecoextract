# PUBLICATION METADATA EXTRACTION

Extract bibliographic metadata from this scientific document.

## Document Format

The document is provided as a JSON array of page objects. Each page contains:

- **page_number**: The page number
- **page_header**: Array of header text lines (often contains journal citation)
- **section_header**: Array of section titles
- **text**: Main body text
- **tables**: Array of table objects
- **other**: Array of figures, captions, and other elements

## CRITICAL: Check page_header First

**The journal name and publication year most commonly appear in the `page_header` field.** Before searching elsewhere, examine:

1. **page_header on first page** - Often contains full citation with journal, volume, pages, year
2. **page_header on subsequent pages** - May contain abbreviated journal name
3. **First lines of text field** - Check if citation appears in body text

**Common patterns** (extract journal text that appears BEFORE the numbers):
- "Comp. Immun. Microbiol. infect. Dis. Vol. 16, No. 1, pp. 77-85, 1993"
  → Journal: "Comp. Immun. Microbiol. infect. Dis." | Year: 1993
- "Journal of Wildlife Diseases, 30(3), 1994, pp. 439-444"
  → Journal: "Journal of Wildlife Diseases" | Year: 1994
- "Nature 423: 145-150 (2003)"
  → Journal: "Nature" | Year: 2003
- Any text followed by volume/issue/page information likely contains the journal name

## Required Fields

### first_author_lastname (CRITICAL)

- Extract **only the last name** of the first author
- Look in: author byline, headers/footers, citation block
- **Pay special attention to anything that looks like a citation**
- Preserve accents and prefixes (e.g., "van den Berg", "O'Connor", "García")

### publication_year (CRITICAL)

- Four-digit publication year (e.g., `2022`)
- Use the **publication year**, not submission/revision dates
- Look in: near author names, headers/footers, citation block, copyright line

## Additional Fields

### title

- Complete article title
- May span multiple lines or include subtitles

### doi

- Digital Object Identifier in format `10.xxxx/xxxxx`
- Look for "DOI:" labels or https://doi.org/ URLs
- Look in: near author names, headers/footers, citation block, copyright line

### journal

- **Journal name**: Extract the journal name if present; it appears as either full name or standard abbreviation
- **Abbreviated names are valid**: Many journals use standard abbreviations (e.g., "J. Wildl. Dis." or "Comp. Immun. Microbiol. infect. Dis."). These are legitimate journal names - extract them as written.
- **Where to look** (check all locations):
  1. **First line/top of document** - Often contains bibliographic citation information
  2. **Headers/footers** - Running header may contain journal name
  3. **Citation block** - Near title and authors
  4. **Publisher line** - Near copyright information
- **What to extract**:
  - Journal titles often appear near volume, issue, page, or year information
  - They may be followed by patterns like "Vol. X", "(Issue)", "pp. X-Y", or years
  - Extract the journal name portion, not the volume/issue/page numbers
  - Include abbreviated forms (text with periods like "Microbiol." is often part of journal names)
- **What to avoid**:
  - Do not extract conference names, book titles, or preprint servers as journals
  - Do not include volume, issue, or page numbers in the journal field

### volume

- Volume number (e.g., `16`, `30`)
- Look for: "Vol. X", "Volume X", or number patterns in citation headers
- Typically appears in `page_header` alongside journal name

### issue

- Issue or number (e.g., `1`, `3`)
- Look for: "No. X", "(X)", or issue numbers in citation headers
- Often appears as `30(3)` or `Vol. 16, No. 1`

### pages

- Page range for the article (e.g., `77-85`, `439-444`)
- Look for: "pp. X-Y", "pages X-Y", or hyphenated numbers
- Found in `page_header` citation strings

### issn

- International Standard Serial Number
- Format: `XXXX-XXXX` (e.g., `0147-9571`)
- Often appears in copyright line or document footer

### publisher

- Publisher name (e.g., `Pergamon Press Ltd`, `Wildlife Disease Association`)
- Look in copyright line, footer, or near publication information
- Extract organization name associated with copyright or publication

### bibliography

- Array of citations from the References/Bibliography/Literature Cited section
- Look for sections titled: "References", "Bibliography", "Literature Cited", "Works Cited"
- Extract each citation as a separate array element
- Preserve the citation format as written in the document
- Include all citations found in the reference list
- If no reference section is found, return empty array or null

## Search Strategy

1. **page_header field** - Check here FIRST for journal and year
2. **section_header field** - May contain title
3. **text field** - Search for citation block, author byline, copyright line
4. **other field** - Check for any citation or metadata elements

Extract all fields you can identify. Leave fields empty if not found. Clean OCR artifacts but preserve diacritics and proper capitalization.

**Remember**: Abbreviated journal names (e.g., "Comp. Immun. Microbiol. infect. Dis.") are VALID - extract them as-is.
