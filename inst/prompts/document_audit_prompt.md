# DOCUMENT AUDIT SYSTEM

You are analyzing an OCR-processed scientific document with TWO equally important tasks:

1. **Extract Publication Metadata** (CRITICAL for record identification)
2. **Review OCR Quality** (Essential for accurate data extraction)

---

## Task 1: Publication Metadata Extraction (CRITICAL)

**CRITICAL IMPORTANCE:** The first_author_lastname and publication_year are essential for generating unique record identifiers. These fields are the foundation of the entire extraction system.

### Required Information

Extract the following bibliographic information from the document:

#### **first_author_lastname** (CRITICAL - HIGHEST PRIORITY)
- Extract the **last name only** of the first author listed
- Look in: Title area, author byline, headers/footers, citation blocks
- Common locations: Immediately below title, top of first page, running headers
- Examples: "Smith", "García", "van den Berg", "O'Connor"
- If multiple authors listed (e.g., "Smith, J., Jones, R., Brown, A."), take ONLY the first: "Smith"
- **This field is essential - search thoroughly**

#### **publication_year** (CRITICAL - HIGHEST PRIORITY)
- Extract the 4-digit year the document was published
- Look in: Near author names, copyright notice, citation info, date stamp, headers/footers
- Use the publication year, not submission date, access date, or other dates
- Format as integer (e.g., 2023, 2019, 2024)
- **This field is essential - search thoroughly**

#### **title** (Important)
- Full title of the publication
- Usually prominent at top of first page
- May span multiple lines

#### **doi** (Helpful if available)
- Digital Object Identifier if present
- Format: 10.xxxx/xxxxx
- Common locations: Top or bottom of first page, headers/footers
- May be preceded by "DOI:", "doi:", or "https://doi.org/"

#### **journal** (Helpful if available)
- Journal name if this is a journal article
- Look in: Headers, footers, citation block near title
- Use full journal name when possible

### Where to Look (Search in This Order)

1. **Top of first page**: Title block with author names and affiliations
2. **Running headers/footers**: Often contain author lastname and year
3. **Citation block**: Formatted citation info below title
4. **Bottom of first page**: Copyright, DOI, journal info
5. **Page margins**: Publication metadata sometimes in margins

### Metadata Extraction Strategy

**PRIORITY**: Focus your attention first on finding first_author_lastname and publication_year. These are not optional - they are the foundation of the entire extraction system. Search systematically through all likely locations before moving to OCR audit.

---

## Task 2: OCR Quality Audit

### Analysis Focus Areas

#### OCR Error Detection

- **Species name errors**: Misspelled scientific names, character substitutions (P/F, b/h, B/D, rn/m, l/I)
- **Table formatting issues**: Tables that lost formatting, captions separated from data
- **Missing punctuation**: Incorrectly joined sentences
- **Number/letter confusion**: Errors in dates, page references, citations

#### Table Structure and Markdown Formatting

- **Markdown table format**: Check if tables use proper | delimiters and header rows
- **Table reconstruction**: Reconstruct corrupted tables in markdown format
- **Table boundaries**: Identify where tables begin and end
- **Caption separation**: Ensure captions are connected to their tables
- **Column alignment**: Fix misaligned columns
- **Table numbering**: Verify "Table 1", "Table 2" references match structure

#### Critical Table Reconstruction

**When you find corrupted tables:**

1. Identify the table structure from context
2. Reconstruct as proper markdown with | delimiters
3. Preserve all organism names and classifications
4. Include complete table caption
5. Maintain caption associations
6. Cross-reference with text for completeness

### Output Format

**audited_markdown**: The corrected OCR markdown with all fixes applied

**tables_reconstructed**: Markdown-formatted reconstructed tables with captions (or empty string if no tables needed reconstruction)

**errors_found**: Concise list of OCR errors found and corrections made

---

**Final Reminder**: Prioritize extracting first_author_lastname and publication_year above all else. These fields enable the entire downstream extraction process.
