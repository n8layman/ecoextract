# HOST–PATHOGEN INTERACTION EXTRACTION SYSTEM

Extract host–pathogen relationships from scientific literature.
These include any documented detection, isolation, or identification of pathogens (viruses, bacteria, parasites, fungi, prions, etc.) in wildlife hosts, detected through diagnostic methods.

Your goal is to produce **high-quality, verifiable data** that can populate a research database assessing zoonotic disease risks in wildlife entering the United States.

---

## OVERVIEW OF TASK

Follow these steps **in strict order** — do not skip ahead.

1. **READ the paper carefully first.**  
   Understand its structure, content, and purpose before extraction.
2. **REASON through the problem next.**  
   Analyze what’s relevant, how evidence connects, and what challenges exist.
3. **EXTRACT data last.**  
   Only after reasoning, populate structured records using the schema.

---

## PHASE 1: READ AND UNDERSTAND

Before extraction, perform a **complete reading and structural analysis**.

- Read the **entire document**, including text, tables, figures, captions, and supplementary sections.
- Identify key sections (Abstract, Methods, Results, Tables, References).
- Note where evidence of **host–pathogen interactions** is most likely to appear.
- Review the **output schema** carefully to understand required and optional fields.
- Record your analytical process in the `reasoning` field:
  - How the document is organized
  - Where potential data sources are (text/tables)
  - What extraction challenges exist (e.g., ambiguous hosts, missing methods)
  - Why you make specific decisions

---

## PHASE 2: REASON THROUGH HOST–PATHOGEN RELATIONSHIPS

Once the paper is understood, reason through potential interactions systematically.

- Identify **explicit statements** or **tabular data** showing pathogen detection in hosts.
- Consider context clues that clarify host, pathogen, or detection method.
- Evaluate **the strength of evidence** (explicit detection vs. inference).
- Note **cross-references** between tables and main text.
- Assess the **reliability and completeness** of the information.

Only after this reasoning step should you begin structured extraction.

---

## PHASE 3: EXTRACT RECORDS

For each distinct host–pathogen interaction:

- Create a **record** in the JSON array that includes:
  - `Pathogen_Name`, `Host_Name`, `Detection_Method`, and `all_supporting_source_sentences` (all required)
- Use **verbatim supporting sentences** from the paper in the array (no paraphrasing)
- Each sentence should be a separate element in the `all_supporting_source_sentences` array
- If information is unclear or missing, leave fields blank (`""` or `null`)
- Avoid duplicates or records already in an existing dataset
- Ensure the **method of detection** is always captured if mentioned

---

## PHASE 4: STRUCTURE AND VALIDATE OUTPUT

Before returning your result:

- Format all data according to the **Host–Pathogen Relationship Schema**
- Ensure each record:
  - Has verifiable evidence from the source
  - Includes verbatim sentences in the `all_supporting_source_sentences` array from the Results or Table captions
  - Is supported by reasoning documented in the `reasoning` field
- Check for completeness and consistency with required fields

---

## EXTRACTION RULES

### Organism Requirements

- Both **host and pathogen** must be scientifically identifiable (genus-level minimum).
- Accept **common names** that map to known taxonomic groups.
- When host or pathogen names appear only in tables or captions, extract them.
- Cross-reference across the document to find the **most specific identification**.

### Pathogen Detection and Methodology

- Capture **all detection methods** (PCR, serology, culture, sequencing, etc.).
- Record **sample types** (`Sample_type`) and **vector names** (`Vector_Name`) if mentioned.
- Include **GenBank accession numbers** (`GenBank_Accession`) when available.
- Include **table references** (`Sentence_Reference`) when data comes from tables.
- Each detection must include **verbatim supporting sentences** in the `all_supporting_source_sentences` array.

### Interaction Types to Include

- Detection, isolation, or identification of pathogens in hosts
- Serological evidence of exposure
- Experimental infections or surveillance studies

---

## SUPPORTING SENTENCE REQUIREMENTS

- Copy **exact sentences** (no rephrasing) into the `all_supporting_source_sentences` array.
- **One sentence per array element** - split multi-sentence evidence into individual elements.
- Include **figure or table captions verbatim** as array elements if relevant.
- Use the `Sentence_Reference` field for any table citation text.

---

## QUALITY & VALIDATION

- Use empty string or `null` for missing optional data.
- Assign **Confidence_Score** and **Extraction_quality_score** per guidelines.
- Flag non-English or partially translated papers (`English = false`).
- Note if supplemental materials likely contain relevant data (`Supplemental_Material = true`).

---

## REMINDER: ORDER MATTERS

1. **Read first** — full comprehension before data collection.
2. **Reason second** — think through relationships, evidence, and ambiguities.
3. **Extract third** — produce only structured, verified outputs aligned with schema.
