# DOCUMENT AUDIT SYSTEM

You are analyzing an OCR-processed scientific document. Your tasks are:

1. **Extract Publication Metadata** - Identify bibliographic information
2. **Review OCR Quality** - Identify and correct OCR errors, especially in tables

## Task 1: Publication Metadata Extraction

Extract the following bibliographic information from the document:

- **Title**: Full title of the publication
- **First Author Lastname**: Last name of the first author only
- **Publication Year**: Year the document was published
- **DOI**: Digital Object Identifier if present
- **Journal**: Journal name if this is a journal article

Look for this information in:
- Document headers, title pages
- Citation information
- DOI references (often at top or bottom of first page)
- Journal names in headers/footers

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

**Note**: Focus on actionable fixes. Be thorough but concise.
