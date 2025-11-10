# Schema Format Guide

## Overview

The schema defines what data fields will be extracted from documents and stored in the database. It must follow a specific JSON Schema format that ecoextract expects.

## Reserved System Fields

**⚠️ IMPORTANT**: The following field name is reserved and automatically managed by ecoextract:

### record_id

- **Format**: `AuthorYear-oN` (e.g., `Smith2020-o1`, `Jones2023-o15`)
- **Purpose**: Unique identifier for each record within a document
- **Generated**: Automatically by the system when records are saved
- **Do NOT include in your schema** - this is a system field

During extraction, `record_id` is hidden from the LLM (generated after extraction). During refinement, `record_id` is shown to the LLM with strict instructions to preserve it exactly.

## Required Structure

Your schema **must** wrap fields in a `records` array:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Your Domain Schema Title",
  "description": "What you're extracting",
  "type": "object",
  "properties": {
    "records": {
      "type": "array",
      "description": "Array of extracted records",
      "items": {
        "type": "object",
        "required": ["field1", "field2"],
        "properties": {
          "field1": {
            "type": "string",
            "description": "Description of field1"
          },
          "field2": {
            "type": "integer",
            "description": "Description of field2"
          }
        }
      }
    }
  },
  "required": ["records"]
}
```

## Key Points

### 1. The `records` wrapper is required

The schema must have this structure:
- Top level: `properties.records`
- Records: `properties.records.items.properties` (your actual fields)

### 2. Supported field types

- `string` → SQL TEXT
- `integer` → SQL INTEGER
- `number` → SQL REAL (decimals)
- `boolean` → SQL BOOLEAN (stored as 0/1)
- `array` → SQL TEXT (stored as JSON)
- `object` → SQL TEXT (stored as JSON)

### 3. Required vs Optional fields

Mark required fields in the `items.required` array:

```json
"items": {
  "type": "object",
  "required": ["pathogen_name", "host_name"],
  "properties": {
    "pathogen_name": { "type": "string" },
    "host_name": { "type": "string" },
    "sample_type": { "type": "string" }  // optional
  }
}
```

### 4. Array fields for multiple values

Use arrays for fields that can have multiple values:

```json
"supporting_sentences": {
  "type": "array",
  "description": "Evidence from document",
  "items": {
    "type": "string",
    "description": "Individual sentence"
  }
}
```

## Common Patterns

### Text extraction with evidence

```json
"pathogen_name": {
  "type": "string",
  "description": "Name of pathogen mentioned in document"
},
"supporting_evidence": {
  "type": "array",
  "description": "Sentences that mention this relationship",
  "items": { "type": "string" }
}
```

### Numeric data with confidence

```json
"prevalence": {
  "type": "number",
  "description": "Infection prevalence reported"
},
"confidence_score": {
  "type": "number",
  "minimum": 0,
  "maximum": 1,
  "description": "LLM confidence in extraction"
}
```

### Optional metadata

```json
"page_number": {
  "type": "integer",
  "description": "Page where data was found"
},
"study_year": {
  "type": "integer",
  "description": "Year of study"
}
```

## Example: Host-Pathogen Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Host-Pathogen Relationships",
  "description": "Pathogen detections in host organisms",
  "type": "object",
  "properties": {
    "records": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["pathogen_name", "host_name", "detection_method"],
        "properties": {
          "pathogen_name": {
            "type": "string",
            "description": "Scientific name of pathogen"
          },
          "host_name": {
            "type": "string",
            "description": "Scientific name of host organism"
          },
          "detection_method": {
            "type": "string",
            "description": "Method used (PCR, serology, etc.)"
          },
          "sample_type": {
            "type": "string",
            "description": "Type of sample tested"
          },
          "supporting_sentences": {
            "type": "array",
            "description": "Evidence from document",
            "items": { "type": "string" }
          },
          "confidence_score": {
            "type": "number",
            "minimum": 0,
            "maximum": 1
          }
        }
      }
    }
  },
  "required": ["records"]
}
```

## Testing Your Schema

After creating your schema:

1. Save as `ecoextract/schema.json`
2. Run `init_ecoextract()` to create template
3. Run `process_documents()` on a test PDF
4. Check database structure: `DBI::dbListFields(con, "records")`

## Troubleshooting

**Error: "Schema must contain 'properties.records'"**
- Your schema is missing the `records` wrapper
- See "Required Structure" above

**Records table not created**
- Check that schema is valid JSON
- Verify the `records.items.properties` path exists

**Missing columns in database**
- Fields must be in `records.items.properties`
- Check spelling matches between schema and extraction prompt
