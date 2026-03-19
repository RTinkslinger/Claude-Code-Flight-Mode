# Iteration 4 — Final Polish

**Date:** 2026-03-18
**Scope:** Fix 4 remaining P1 issues from code review, unify test runner

## Fixes Applied

### P1-1: `routeData.route.split('-')` crash guard
**File:** `templates/dashboard.html:375`
**Change:** `routeData.route.split('-')[1]` → `(routeData.route || '').split('-')[1]`
**Reason:** Prevents TypeError when route is undefined in malformed route-data.json

### P1-2: Latest-point dots at -1 sentinel values
**File:** `templates/dashboard.html:285-286`
**Change:** Added `>= 0` guard before rendering each latency dot
**Reason:** Prevents dots rendering below chart axis for offline measurements

### P1-3: Unified test runner
**File:** `tests/run-tests.sh`
**Change:** Added V2 sub-test suite invocation block that runs all 9 `test-v2-*.sh` files and aggregates results
**Reason:** `run-tests.sh` was only running 74 core tests — new test files were orphaned

### P1-4: Missing takeoff_time test assertion
**File:** `tests/test-v2-lookup.sh`
**Change:** Added LK.6d test that verifies `takeoff_time` is a valid ISO timestamp in route-data.json
**Reason:** The C3 P0 fix (takeoff_time was always null) had no test coverage

## Final Regression

```
Total: 247 tests
Passed: 246
Failed: 0
Skipped: 1 (SQ.2b — root-commit edge case, documented)
```

All 9 sub-test suites pass through the unified runner.

## Status: Production Ready

No P0 or P1 issues remain. Remaining P2/P3 items are cosmetic/style concerns documented in `iteration-3-code-review.md`.
