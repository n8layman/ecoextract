# PUBLICATION METADATA EXTRACTION

Extract bibliographic metadata from this scientific document.

## CRITICAL: Check the First Line/Header First

**The journal name and publication year most commonly appear in the very first line or header of the document.** Before searching elsewhere, examine:

1. **First line of the document** - Look for text before volume/issue numbers or page ranges
2. **Top header/footer** - May contain journal abbreviation and year
3. **Running header** - Journal name often repeated on each page

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

### journal (CRITICAL)

- **Journal name**: Extract the journal name if present; it may appear as the full name or as a standard abbreviation/short name.
- **ABBREVIATED NAMES ARE ACCEPTABLE**: "Comp. Immun. Microbiol. infect. Dis." is a valid journal name - extract it as-is
- **Where to look** (in priority order):
  1. **FIRST LINE of document** - Most common location, usually format "Journal Name, Vol. X, No. Y, pp. ZZZ, YEAR"
  2. **Top header/footer** - Running header on first page
  3. **Citation block** - Near author names, may say "Published in..."
  4. **Publisher line** - Near copyright or publisher information
- **Instructions**:
  1. Check the FIRST LINE before searching elsewhere
  2. Look for patterns like "Vol." or "No." - the journal name usually appears immediately before these
  3. Extract abbreviated journal names (e.g., "J. Wildl. Dis.") - do not skip them
  4. Pay special attention to anything that looks like a citation
  5. Ignore references to conferences, book chapters, or preprint servers unless they are clearly the journal

## Search Strategy

1. **FIRST LINE / TOP HEADER** - Check here FIRST for journal and year
2. **Citation block** - Most reliable for all fields
3. **Title and author section**
4. **Headers or footers** - Often contain journal abbreviation
5. **Copyright or publisher line**

Extract all fields you can identify. Leave fields empty if not found. Clean OCR artifacts but preserve diacritics and proper capitalization.

**Remember**: Abbreviated journal names (e.g., "Comp. Immun. Microbiol. infect. Dis.") are VALID - extract them as-is.
