# Record Rediscovery Test Documentation

## Purpose

This test validates that `ecoextract` can **rediscover records that were physically deleted from the database** when re-running extraction on the same document.

This is a critical feature because:
- Users may accidentally delete records from the database
- Database corruption could cause record loss
- Users may want to re-extract from scratch without losing already-processed OCR/metadata

## Test Location

[tests/testthat/test-integration.R:56-141](tests/testthat/test-integration.R#L56)

## Test Steps

### 1. Initial Extraction (First Run)
```r
result1 <- process_documents(test_pdf, db_conn = db_path, ...)
```
- Runs full pipeline: OCR → Metadata → Extraction → Refinement
- Extracts N records from test PDF (e.g., N=7)
- Saves records to database
- Verifies all steps completed successfully

**State after Step 1:** Database contains 7 records

### 2. Physical Deletion (Simulate Data Loss)
```r
# Delete half the records (floor(7/2) = 3 records)
DELETE FROM records WHERE record_id IN (...)
```
- Physically deletes ~50% of records from database
- This simulates accidental deletion or data corruption
- No soft delete flag - records are **gone**

**State after Step 2:** Database contains 4 records (7 - 3 = 4)

### 3. Re-extraction (Second Run)
```r
result2 <- process_documents(test_pdf, db_conn = db_path, ...)
```
- OCR is **skipped** (already exists in documents table)
- Metadata is **skipped** (already exists)
- Extraction **runs again** (re-extracts from same OCR content)
- Deduplication compares new extraction against existing 4 records

**Expected behavior:**
- Extraction should find all 7 records again (same document, same prompt)
- Deduplication should detect that 4 records already exist
- Should save the 3 "new" records (which are actually the deleted ones)

**State after Step 3:** Database should contain 7 records again (4 kept + 3 rediscovered)

## How Deduplication Enables Rediscovery

The deduplication logic in [R/extraction.R:119-150](R/extraction.R#L119) works as follows:

```r
# Get existing records for this document
existing_records <- get_records(document_id, db_conn)  # Returns 4 records

# Deduplicate new extraction against existing
dedup_result <- deduplicate_records(
  new_records = extraction_df,        # 7 newly extracted records
  existing_records = existing_records, # 4 records still in DB
  ...
)

# Save only unique records (the 3 that were deleted)
save_records_to_db(..., unique_records, mode = "insert")
```

**Key insight:** Deduplication compares the fresh extraction (7 records) against what's currently in the database (4 records), allowing the 3 deleted records to be identified as "unique" and re-inserted.

## Test Assertions

### Assertion 1: Rediscovery Occurred
```r
expect_true(final_count > after_delete_count)
# 7 > 4 ✓
```
Verifies that extraction found and saved the deleted records.

### Assertion 2: No Duplication of Kept Records
```r
expect_true(final_count <= initial_count * 1.5)
# 7 <= 10.5 ✓
```
Verifies that the 4 records that were NOT deleted weren't duplicated. Allows 50% margin for LLM non-determinism (might extract slightly different records).

## Why This Test Fails Intermittently

The test can fail when:

1. **LLM non-determinism**: Second extraction finds fewer records than first
   - First run: 7 records
   - Second run: Only 5 records extracted
   - After deleting 3, DB has 4 records
   - Re-extraction finds 5, deduplication keeps 1 new → final count = 5
   - **Assertion fails:** 5 > 4 ✓ but 5 < 7 ✗

2. **Deduplication false positives**: Similarity threshold catches slight variations
   - Using `jaccard` with `min_similarity=0.9`
   - If LLM rephrases a field slightly differently, dedup might mark it as duplicate
   - Deleted record not recognized as "new" due to slight content variation

3. **Extraction variability**: Different prompts/models may extract different subsets
   - Not all records are deterministically extractable
   - Some papers have ambiguous data that LLM might skip on second pass

## Current Status

**Failing intermittently** - The test expects deterministic LLM behavior but:
- Different runs may extract different numbers of records
- Field-by-field comparison is sensitive to wording changes
- Using Jaccard similarity to avoid API costs, but it's less robust than embeddings

## Potential Solutions

1. **Use embedding similarity** instead of Jaccard for more robust matching
2. **Lower expectations** - Test that `final_count >= after_delete_count` (at least doesn't lose more)
3. **Add tolerance** - Allow final count to be within range: `initial_count ± 2`
4. **Mock the extraction** - Use fixed extraction results instead of real LLM calls
5. **Skip the test** - Mark as known intermittent and skip in CI

## Related Code

- Extraction logic: [R/extraction.R:20-170](R/extraction.R#L20)
- Deduplication logic: [R/deduplication.R](R/deduplication.R)
- Test helper: [tests/testthat/test-integration.R:56](tests/testthat/test-integration.R#L56)
