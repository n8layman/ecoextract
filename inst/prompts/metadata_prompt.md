# PUBLICATION METADATA EXTRACTION (UPDATED PRIORITY)

Extract bibliographic metadata from this scientific document.

## Document Format

The document is provided as a JSON array of page objects. Each page contains:

- **page_number**: The page number
- **page_header**: Array of header text lines (often contains journal citation)
- **section_header**: Array of section titles
- **text**: Main body text
- **tables**: Array of table objects
- **other**: Array of figures, captions, and other elements

---

## CRITICAL: Check page_header First

The journal name and publication year most commonly appear in the `page_header` field. Before searching elsewhere, examine:

1. **page_header on first page** – often contains full citation with journal, volume, pages, year
2. **page_header on subsequent pages** – may contain abbreviated journal name
3. **First lines of text field** – check if citation appears in body text

**Common patterns**:

- `"Comp. Immun. Microbiol. infect. Dis. Vol. 16, No. 1, pp. 77-85, 1993"` → Journal: `"Comp. Immun. Microbiol. infect. Dis."`, Year: 1993
- `"Journal of Wildlife Diseases, 30(3), 1994, pp. 439-444"` → Journal: `"Journal of Wildlife Diseases"`, Year: 1994
- `"Nature 423: 145-150 (2003)"` → Journal: `"Nature"`, Year: 2003

Any text followed by volume/issue/page information likely contains the journal name.

---

## High-Priority Fields (Extract if at all possible)

### first_author_lastname

- **Always extract**; this is critical.
- Extract **only the last name** of the first author.
- Look in: author byline, headers/footers, citation block.
- Preserve accents and prefixes (e.g., `"van den Berg"`, `"O'Connor"`, `"García"`).

### publication_year

- **Always extract**; critical for bibliographic context.
- Four-digit year (e.g., `2022`).
- Look near author names, headers/footers, citation block, copyright line.

---

## Secondary Fields (Extract wherever present)

These fields are **high priority to capture** if any evidence exists. Attempt extraction carefully:

- **title** – Complete article title; may span multiple lines.
- **doi** – Digital Object Identifier (`10.xxxx/xxxxx`) or `https://doi.org/...`.
- **journal** – Full or abbreviated journal name. Include abbreviations; exclude volume/issue/page numbers.
- **volume** – Numeric volume number.
- **issue** – Issue number.
- **pages** – Page range (e.g., `77-85`).
- **issn** – International Standard Serial Number (`XXXX-XXXX`).
- **publisher** – Organization name associated with publication.
- **authors** – Array of author names if available; otherwise leave empty/null. Do not fail if missing.
- **bibliography** – Array of reference strings from References/Bibliography/Literature Cited sections. Leave empty/null if none found.

> **Important:** Treat all secondary fields as high-priority to extract, not optional. Model should attempt to populate as much as possible.

---

## Extraction Strategy

1. **page_header** – first check for journal, volume, pages, year.
2. **section_header** – may contain article title.
3. **text** – search for citation block, author byline, copyright line.
4. **other** – check captions, figures, tables, or other metadata hints.

- Clean OCR artifacts but preserve diacritics, capitalization, and punctuation.
- Populate fields with empty string or `null` only if extraction fails.
- Prioritize completeness for all high-priority fields, including authors list and bibliography.
