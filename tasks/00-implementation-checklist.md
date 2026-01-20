# Skip/Cascade Logic Implementation Checklist

## Overview

This checklist tracks the implementation of skip and cascade logic for the document processing pipeline. See [SKIP_LOGIC.md](../SKIP_LOGIC.md) for the full design document.

## Implementation Order

Tasks are ordered by: (1) dependencies - foundational work first, (2) complexity - simpler tasks first.

### Phase 1: Foundation (Helper Functions)

These have no dependencies and are required by everything else.

- [ ] **Task 1: Create `is_forced()` helper** - [02-force-reprocess-params.md](02-force-reprocess-params.md)
  - Simple function, no dependencies
  - Required by: all skip logic

- [ ] **Task 2: Create `should_run_step_status_only()` helper** - [03-extraction-skip-logic.md](03-extraction-skip-logic.md)
  - Simpler than `should_run_step()` (no desync handling)
  - Depends on: `is_forced()`

- [ ] **Task 3: Create `should_run_step()` helper** - [06-status-first-skip.md](06-status-first-skip.md)
  - Includes desync detection logic
  - Depends on: `is_forced()`

### Phase 2: Parameter Updates

Update function signatures before changing behavior.

- [ ] **Task 4: Update `force_reprocess_*` parameters** - [02-force-reprocess-params.md](02-force-reprocess-params.md)
  - Change from boolean to NULL/TRUE/integer vector
  - Add `force_reprocess_extraction` parameter
  - Add validation
  - Depends on: `is_forced()` helper

- [ ] **Task 5: Update `run_refinement` parameter** - [04-run-refinement-param.md](04-run-refinement-param.md)
  - Change from boolean to FALSE/TRUE/integer vector
  - Add validation
  - Independent of other parameter changes

### Phase 3: Skip Logic

Wire up the helpers to actual workflow.

- [ ] **Task 6: Add skip logic to Extraction** - [03-extraction-skip-logic.md](03-extraction-skip-logic.md)
  - Uses `should_run_step_status_only()`
  - Remove hardcoded `force_reprocess = FALSE`
  - Depends on: Tasks 1-4

- [ ] **Task 7: Update OCR/Metadata to status-first** - [06-status-first-skip.md](06-status-first-skip.md)
  - Uses `should_run_step()`
  - Depends on: Tasks 1-4

- [ ] **Task 8: Add desync handling** - [01-desync-handling.md](01-desync-handling.md)
  - Part of `should_run_step()` implementation
  - Depends on: Task 7

### Phase 4: Cascade

Requires all skip logic to be working first.

- [ ] **Task 9: Add cascade tracking** - [05-cascade-tracking.md](05-cascade-tracking.md)
  - Add `ocr_ran`, `metadata_ran` flags
  - Pass `upstream_ran` to helpers
  - Add status nullification on force
  - Depends on: Tasks 6-8

### Phase 5: Testing

- [ ] Test `is_forced()` with NULL, TRUE, integer vector
- [ ] Test skip logic for each step
- [ ] Test `force_reprocess_*` with TRUE and integer vector
- [ ] Test desync detection (OCR, Metadata)
- [ ] Test cascade (OCR -> Metadata -> Extraction)
- [ ] Test `run_refinement` with integer vector
- [ ] Test zero records is valid extraction result

## Dependency Graph

```text
is_forced() ─────────────────────────────────────────┐
     │                                               │
     ├──> should_run_step_status_only()              │
     │              │                                │
     │              └──> Extraction skip logic ──────┤
     │                                               │
     └──> should_run_step() ──> OCR/Metadata skip ───┤
                    │                 │              │
                    └──> Desync ──────┘              │
                                                     │
force_reprocess_* params ────────────────────────────┤
                                                     │
run_refinement param ────────────────────────────────┤
                                                     │
                                                     v
                                            Cascade tracking
```

## Files to Modify

| File | Changes |
| ---- | ------- |
| `R/workflow.R` | Helper functions, parameter updates, skip logic, cascade tracking |
| `R/ocr.R` | May need to remove internal skip logic |
| `R/metadata.R` | May need to remove internal skip logic |
| `R/extraction.R` | Update or remove unused `force_reprocess` param |

## Task File Reference

| # | Task | File | Complexity |
| - | ---- | ---- | ---------- |
| 1 | `is_forced()` helper | [02-force-reprocess-params.md](02-force-reprocess-params.md) | Low |
| 2 | `should_run_step_status_only()` | [03-extraction-skip-logic.md](03-extraction-skip-logic.md) | Low |
| 3 | `should_run_step()` | [06-status-first-skip.md](06-status-first-skip.md) | Medium |
| 4 | `force_reprocess_*` params | [02-force-reprocess-params.md](02-force-reprocess-params.md) | Low |
| 5 | `run_refinement` param | [04-run-refinement-param.md](04-run-refinement-param.md) | Low |
| 6 | Extraction skip logic | [03-extraction-skip-logic.md](03-extraction-skip-logic.md) | Medium |
| 7 | OCR/Metadata status-first | [06-status-first-skip.md](06-status-first-skip.md) | Medium |
| 8 | Desync handling | [01-desync-handling.md](01-desync-handling.md) | Medium |
| 9 | Cascade tracking | [05-cascade-tracking.md](05-cascade-tracking.md) | High |
