# EcoExtract TODO

## High Priority

### Issue #34: Fix record_id format
Currently: `AuthorYear-0N` (e.g., `MCLEAN1979-o1`)
Should be: `Author_Year_X_Y` (e.g., `MCLEAN_1979_1_1`)
- X differentiates multiple papers from same author/year
- Y is the record number (use 'r' prefix for 'record')
- Consider using primary key for records table with auto-increment

### Issue #31: Rename document table id column
Document table id column should be called `document_id` for consistency when joining with records table

### Issue #30: Remove optional labels from schema
Extract everything available. Don't give the model the option to skip fields.

### Issue #29: Collapse optional sentences into single JSON
Optional sentences adds complexity. Have the model find all relevant sentences from anywhere in the document and return them verbatim as a single JSON object or list.

### Issue #32: Fix metadata extraction when citation in first page
Metadata extraction not working for some documents (e.g., 18-0411.pdf). Possibly because ohseer is missing footer?

## Medium Priority

### Issue #33: Create export_db() function
Join on document_id, have parameters for simple mode and to return OCR data (default false). Should return a tibble and optionally export as CSV if filename passed.

### Issue #25: Add extraction record summary in metadata table
Review columns, order them logically, and include metadata about the extraction (number of records extracted, etc.)

### Issue #26: Add step status to metadata
Add status column to documents table to track if metadata extraction failed or succeeded at each step.

### Issue #23: Add extraction data to metadata
Track how many records were extracted in total for each paper.

### Issue #24: Debug reasoning field not always exported
Figure out why the reasoning text is sometimes not being output during extraction.

### Issue #16: Make process_documents pdf input parameter more flexible
Support three input types:
1. Single file path: `"path/to/document.pdf"`
2. Vector of file paths: `c("doc1.pdf", "doc2.pdf")`
3. Folder path: `"path/to/folder/"` - process all PDFs in the folder

### Issue #14: Verify Tensorlake OCR output structure
Verify if `page_footer` field exists and update prompts accordingly. Check for any other missing fields.

### Issue #20: Check why reasoning says only 2 pages available
Might be due to old version of ohseer. Should OCR all pages by default with optional pages parameter.

## Low Priority / Review

### Issue #28: Evaluate confidence score vs extraction_quality score
Determine if these are redundant.

### Issue #27: Remove OCR audit column from documents schema
Clean up unnecessary columns.

### Issue #21: Add literature cited to document metadata
Extract literature cited section during metadata extraction (nice to have).

### Issue #13: Implement Claude prompt caching for cost optimization
Implement prompt caching and/or Message Batches API to reduce costs. Claude-specific feature that adds complexity but could significantly reduce costs for bulk processing.
