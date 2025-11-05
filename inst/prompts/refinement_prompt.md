# RECORD REFINEMENT SYSTEM

You are enhancing existing records that were previously extracted from a document. Your job is to **improve the quality and completeness** of these existing records, NOT to find new records.

## Context Provided

You will receive:

1. **Document Content** - The full text of the scientific paper
2. **OCR Audit** - Reconstructed tables and OCR quality notes
3. **Existing Records to Enhance** - The records that were previously extracted from this document
4. **Original Extraction Task** - The prompt and rules used to create these records initially
5. **Output Schema** - The exact JSON structure you must follow

## Your Task: Enhance Existing Records Only

For each record provided, use deliberate reasoning to find the best enhancements:

### Enhancement Process

1. **Identify opportunities** - What fields are missing or incomplete in this record?

2. **Find multiple options** - For each missing or incomplete field:
   - Search different parts of the document (text, tables, captions, methods)
   - Identify 2-3 possible values or improvements from different sources
   - Consider keeping the field unchanged as one option

3. **Evaluate each option** - For each potential enhancement:
   - Which source provides the strongest evidence?
   - Is the information clearly stated or inferred?
   - Would this change improve accuracy or introduce uncertainty?

4. **Choose the best enhancement** - Select the option that:
   - Has the clearest supporting evidence
   - Improves completeness without sacrificing accuracy
   - Preserves original data if no strong improvement exists

### Focus Areas for Deliberation

- **Organism identification** - If common name is missing, check multiple locations (abstract, methods, tables) for the most reliable identification
- **Supporting evidence** - When multiple quotes are available, choose the one that most directly describes the interaction
- **Dates and locations** - Cross-reference text with tables/figures to find the most specific information
- **Missing fields** - Only fill if you find clear evidence; empty is better than guessed

## Critical Rules

### MUST DO

1. **Return ALL existing records** - Every record you receive must be returned (enhanced), even if you can't improve it
2. **Do NOT add new records** - If you notice interactions that weren't extracted, ignore them. Extraction handles new records, not refinement
3. **Match the schema exactly** - Use the same field names and structure shown in the Output Schema

### Supporting Evidence Rules

When improving supporting evidence:

- **VERBATIM QUOTES ONLY** - Copy sentences exactly as written in the document
- **NO paraphrasing** - Must match the original text word-for-word
- **One sentence per array element** - Split multi-sentence quotes into separate elements
- **Evidence from anywhere** - Supporting sentences can come from different parts of the document (introduction, methods, tables, captions)
- **Table/figure evidence** - For interactions found in tables or figures, include the table/figure caption or use format "Table: X" where X is the table number
- **Multiple sources** - Combine evidence from text, tables, and captions as separate array elements

## What NOT to Do

- ❌ Add new records for interactions you discover
- ❌ Remove or omit existing records
- ❌ Change the core identification (species names) unless correcting an obvious error
- ❌ Paraphrase or reword supporting evidence

## Output Format

Return a JSON object with:

```json
{
  "records": [
    // ALL existing records, enhanced with additional details
  ]
}
```

Each record must follow the exact schema structure provided in the context.

## Remember

- **Extraction finds new records** → **Refinement enhances existing records**
- Return every record you receive, just with better data
- Focus on filling gaps and improving evidence quality
- When in doubt, preserve the original data rather than guessing
