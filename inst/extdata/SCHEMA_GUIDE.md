# Schema Format Guide

## Overview

The schema defines what data fields will be extracted from documents and stored in the database. It must follow a specific JSON Schema format that ecoextract expects and that is compatible with all supported LLM providers (Claude, GPT, Mistral).

## Reserved System Fields

**IMPORTANT**: The following field name is reserved and automatically managed by ecoextract:

### record_id

- **Format**: `AuthorYear-oN` (e.g., `Smith2020-o1`, `Jones2023-o15`)
- **Purpose**: Unique identifier for each record within a document
- **Generated**: Automatically by the system when records are saved
- **Do NOT include in your schema** - this is a system field

During extraction, `record_id` is hidden from the LLM (generated after extraction). During refinement, `record_id` is shown to the LLM with strict instructions to preserve it exactly.

## Required Structure

Your schema **must** wrap fields in a `records` array and follow [OpenAI's structured output requirements](https://platform.openai.com/docs/guides/structured-outputs/supported-schemas) for cross-provider compatibility:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Your Domain Schema Title",
  "description": "What you're extracting",
  "type": "object",
  "additionalProperties": false,
  "required": ["records"],
  "properties": {
    "records": {
      "type": "array",
      "description": "Array of extracted records",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["field1", "field2", "optional_field"],
        "properties": {
          "field1": {
            "type": "string",
            "description": "A required string field"
          },
          "field2": {
            "type": "integer",
            "description": "A required integer field"
          },
          "optional_field": {
            "type": ["string", "null"],
            "description": "An optional field - returns null when not available"
          }
        }
      }
    }
  }
}
```

Key requirements:

- Top-level must have a `records` property (array of objects)
- Each field should have a `type` and `description`
- Use `x-unique-fields` to identify fields that define uniqueness (used for deduplication and accuracy)
- Every object must have `"additionalProperties": false`
- **All** properties must be listed in `required` -- use nullable types for optional fields

## Cross-Provider Compatibility

ecoextract supports multiple LLM providers (Anthropic Claude, OpenAI GPT, Mistral). To ensure schemas work across all providers, follow [OpenAI's structured output requirements](https://platform.openai.com/docs/guides/structured-outputs/supported-schemas):

1. **`additionalProperties: false`** on every object definition
2. **All properties listed in `required`** -- every field in `properties` must also appear in `required`
3. **Nullable types for optional fields** -- use `"type": ["string", "null"]` instead of omitting from `required`. The model returns `null` when no data is available
4. **No `minimum`/`maximum` constraints** -- put range info in the `description` instead (e.g., `"description": "Confidence score (1-5 scale)"`)
5. **No `$ref`** -- inline all definitions
6. **Max 100 properties, 5 nesting levels**

These rules are safe for all providers -- Claude and Mistral handle them without issues.

## Supported Field Types

| JSON Type | SQLite Type | R Type | Example |
|-----------|-------------|--------|---------|
| `string` | TEXT | character | "Myotis lucifugus" |
| `integer` | INTEGER | integer | 2023 |
| `number` | REAL | numeric | 45.123 |
| `boolean` | BOOLEAN | logical | true |
| `array` | TEXT (JSON) | list | ["sentence 1", "sentence 2"] |
| `object` | TEXT (JSON) | list | {"lat": 45, "lon": -122} |

For optional scalar fields, use nullable types: `["string", "null"]`, `["integer", "null"]`, etc.
For optional array fields, use plain `"array"` type -- the model returns `[]` when no data is available. Do NOT use `["array", "null"]`.

## Structural vs Data Requirements

The `required` array serves a **structural** purpose: OpenAI requires every property to be listed in `required`. This does not mean every field must contain data.

**Data requirements** are expressed through types:

- **Must have data**: plain type (`"type": "string"`) -- the model must provide a value
- **Data optional**: nullable type (`"type": ["string", "null"]`) -- the model returns `null` when no data is available; stored as NULL in the database
- **Array, may be empty**: plain array (`"type": "array"`) -- the model returns `[]` when no data is available; stored as `"[]"` in the database

```json
"items": {
  "type": "object",
  "additionalProperties": false,
  "required": ["pathogen_name", "host_name", "sample_type", "detection_methods"],
  "properties": {
    "pathogen_name": { "type": "string", "description": "Always present" },
    "host_name": { "type": "string", "description": "Always present" },
    "sample_type": { "type": ["string", "null"], "description": "Null if not mentioned" },
    "detection_methods": { "type": "array", "items": { "type": "string" }, "description": "Empty array if not mentioned" }
  }
}
```

## Array Fields for Multiple Values

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

For optional array fields, use a plain array -- the model returns an empty `[]` when no data is available:

```json
"detection_methods": {
  "type": "array",
  "description": "Methods used (empty array if not mentioned)",
  "items": {
    "type": "string",
    "description": "Individual detection method"
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
  "type": ["number", "null"],
  "description": "Infection prevalence reported (0.0 to 1.0)"
},
"confidence_score": {
  "type": ["integer", "null"],
  "description": "LLM confidence in extraction accuracy (1-5 scale)"
}
```

### Optional metadata

```json
"page_number": {
  "type": ["integer", "null"],
  "description": "Page where data was found"
},
"study_year": {
  "type": ["integer", "null"],
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
  "additionalProperties": false,
  "required": ["records"],
  "properties": {
    "records": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "pathogen_name",
          "host_name",
          "detection_method",
          "sample_type",
          "supporting_sentences",
          "confidence_score"
        ],
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
            "type": ["string", "null"],
            "description": "Type of sample tested"
          },
          "supporting_sentences": {
            "type": "array",
            "description": "Evidence from document",
            "items": { "type": "string" }
          },
          "confidence_score": {
            "type": ["integer", "null"],
            "description": "Extraction confidence (1-5 scale)"
          }
        }
      }
    }
  }
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

**Error: "additionalProperties is required to be supplied and to be false" (OpenAI)**
- Add `"additionalProperties": false` to every object definition
- See "Cross-Provider Compatibility" above

**Error: "is not in the required list" (OpenAI)**
- All properties must be listed in `required`
- Use nullable types (`["string", "null"]`) for optional fields

**Records table not created**
- Check that schema is valid JSON
- Verify the `records.items.properties` path exists

**Missing columns in database**
- Fields must be in `records.items.properties`
- Check spelling matches between schema and extraction prompt
