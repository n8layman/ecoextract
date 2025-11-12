# PUBLICATION METADATA EXTRACTION

Extract bibliographic metadata from this scientific document.

## Required Fields

### first_author_lastname (CRITICAL)

- Extract **only the last name** of the first author
- Look in: author byline, headers/footers, citation block
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

- **Journal name**: Extract the journal name if present; it may appear as the full name or as a standard abbreviation/short name.
- **Where to look**: Check the citation block on the first page, as well as headers, footers, and the publisher line.
- **Instructions**:
  1. Look for explicit phrases like “Published in”, “Journal of …”, or standard citation formats.
  2. Ignore references to conferences, book chapters, or preprint servers unless they are clearly the journal.

## Search Strategy

1. **Citation block** (bottom of first page) - most reliable
2. **Title and author section** (top of first page)
3. **Headers or footers**
4. **Copyright or publisher line**

Extract all fields you can identify. Leave fields empty if not found. Clean OCR artifacts but preserve diacritics and proper capitalization.
