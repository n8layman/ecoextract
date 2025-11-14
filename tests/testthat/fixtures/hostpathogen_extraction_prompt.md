# HOST-PATHOGEN INTERACTION EXTRACTION SYSTEM

Extract host-pathogen relationships from scientific literature for the One Health PROTECT project. Host-pathogen interactions include any documented occurrence of pathogens (viruses, bacteria, parasites, fungi, prions, etc.) in wildlife host species, including detection, isolation, or identification through various diagnostic methods.

**Your output will be used by researchers building a database of zoonotic disease risks in wildlife entering the United States.** The data must be accurate, well-supported, and structured for database storage and analysis.

## Extraction Process

Complete these phases in order for systematic extraction:

### Phase 1: Read and Understand

- Read the entire document content, OCR audit, and existing records section
- Identify the document structure (text, tables, figures, captions)
- Review the output schema to understand required fields

### Phase 2: Find Host-Pathogen Interactions

- Search text for descriptions of pathogen detection in host organisms
- Note figure/table captions that describe pathogen identification or detection methods
- Scan tables for species-pathogen associations, detection data, or diagnostic results
- Cross-reference between text and tables for complete information
- Look for study locations, sample dates, and diagnostic methodology

### Phase 3: Extract Records

- For each host-pathogen interaction found, create a record with all available fields
- Include verbatim supporting sentences from the document
- Skip interactions already listed in the existing records section
- Ensure both host and pathogen are identifiable (at least genus-level)
- Document all identification/detection methods used

### Phase 4: Structure Output

- Format all records according to the output schema
- Verify each record has supporting evidence
- Return the complete records array

## Extraction Rules

### Organism Requirements

- **Both organisms must be identifiable**: Provide the scientific name, genus, or other identifying information for both host and pathogen. In some cases, the identity may need to be inferred from context elsewhere in the document.
- **Genus-level identification is acceptable** from common names that refer to well-established taxonomic groups
- **Host taxonomy standardization**: Standardize host names against GBIF or other taxonomic backbone when possible
- **Organism identity may only be present in tables** - also check figure and table captions for identifying information
- **Recognize taxonomic group identifications** - common names that refer to taxonomic groups (family, genus) provide sufficient organism identification
- **Interpret tabular evidence** - when tables list pathogen detection, isolation, or identification in host species, treat this as evidence of interaction
- **Cross-reference throughout document** for the most specific identification available

### Pathogen Detection and Identification

- **Document all diagnostic methods**: Provide as an array (e.g., `["PCR", "Serology", "Culture"]`)
- **Include method details**: When specific protocols or assays are mentioned, include them in the Detection_Method array
- **Capture sample information**: Provide sample types as an array (e.g., `["blood", "tissue", "tick midgut"]`)
- **Record vector information**: Provide vector species as an array (e.g., `["Ixodes persulcatus", "Ixodes ovatus"]`)
- **Capture GenBank accessions**: Provide as an array when multiple accessions are mentioned

### Interaction Types to Include

- **Pathogen Detection**: Any documented presence of pathogen in host organism (detect, identify, serosurvey)
- **Disease Cases**: Clinical or subclinical infections
- **Surveillance Data**: Screening results, prevalence studies
- **Experimental Infections**: Laboratory studies documenting host-pathogen relationships
- **Molecular Detection**: PCR, sequencing, or other molecular evidence
- **Serological Evidence**: Antibody detection indicating exposure

### Supporting Sentence Requirements

- **VERBATIM QUOTES ONLY** - copy sentences word-for-word from the document text
- **NO paraphrasing or rewording** - sentences must match exactly as written in the source
- **Array format** - provide all supporting sentences as an array, with one sentence per array element
- **Generally from Results section** - sentences should describe the relationship between host and pathogen
- **Include table captions verbatim** when referencing tables/figures
- **Include organism identification sentences** exactly as written
- **Include methodology sentences** that describe detection/identification methods
- **Multiple sentences per record** - collect ALL sentences that support the same pathogen-host-detection combination into a single record

### Critical Validation

- **Leave fields empty if information unavailable** (use empty string or null for optional fields)
- **Extract ALL relevant host-pathogen interactions**
- **Ensure diagnostic methods are documented** - this is a critical requirement for One Health PROTECT
- **Flag non-English papers** - set English field to false if the language could affect extraction quality
- **Note supplemental materials** - set Supplemental_Material to true if more information might be in supplements

## Output Schema

Return a JSON array with records. Each record represents ONE unique pathogen-host-detection method combination. Multiple supporting sentences for the same combination should be in a single record's array.

### Required Fields

- **OHP_Pathogen_Name**: The pathogen of interest that was queried in PubMed (folder name)
- **PDF_Name**: PDF file name
- **Pathogen_Name**: Pathogen name extracted from PDF
- **Host_Name**: Host name extracted from PDF
- **Detection_Method**: Detection method (PCR, Serology, etc.)
- **all_supporting_source_sentences**: Array of verbatim sentences supporting this relationship (multiple sentences per record)

### Optional Fields

- **DOI**: DOI from PDF
- **Sample_type**: Identity of samples tested (e.g., for ticks vs tick hosts)
- **Confidence_Score**: Your confidence in the accuracy of this extraction (5-point scale: 1, 2, 3, 4, or 5):
  - 5 = Very high: Explicit statement in text, clear organism IDs, specific method details
  - 4 = High: Clear relationship stated, good organism IDs, method mentioned
  - 3 = Moderate: Relationship implied or from table, some ambiguity in IDs or method
  - 2 = Low: Significant inference required, vague IDs, or missing method details
  - 1 = Very low: Heavy interpretation needed, poor organism ID, or questionable relationship
- **Vector_Name**: Vector name from PDF
- **GenBank_Accession**: GenBank accession numbers from PDF (comma-separated if multiple)
- **Extraction_quality_score**: Quality of the source data for this record (5-point scale: 1, 2, 3, 4, or 5):
  - 5 = Excellent: Primary research data, specific methods, clear IDs, explicit results
  - 4 = Good: Clear methods and results, good organism identification
  - 3 = Fair: Some details missing, organism ID from common names, or limited method info
  - 2 = Poor: Minimal details, ambiguous identifications, or cited secondary sources
  - 1 = Very poor: Vague information, poor organism ID, or highly aggregated data
- **English**: Boolean flag (false if non-English could affect quality)
- **Supplemental_Material**: Boolean flag (true if supplements might have more info)

## Important Notes

- **OHP_Pathogen_Name** is the query pathogen - the thing they searched for in PubMed
- **Output format**: Records should be structured as CSV-compatible data
- **Pathogen taxonomic standardization**: Use established pathogen taxonomy when possible
- **Search structure guidance**: Look for detect/identify/serosurvey patterns to guide extraction of pathogenic interactions
- **Quality assessment**: Provide both confidence and extraction quality scores when possible

**IMPORTANT**: Use empty string or `null` for optional fields when no data is available. Do not use "UNKNOWN" or placeholder text.
