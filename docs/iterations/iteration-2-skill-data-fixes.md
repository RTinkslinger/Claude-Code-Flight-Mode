# Iteration 2: Skill & Data Fixes

**Date:** 2026-03-18
**Scope:** 8 fixes across skill files, data files, and scripts

## Fixes Applied

### CRITICAL

1. **FIX 1: `/flight-off` doesn't stop dashboard** — Added Step 6.5 between Archive and Remove steps to stop the dashboard server (port 8234) via `dashboard-server.sh`.
   - File: `skills/flight-off/SKILL.md`

2. **FIX 2: Squash logic broken** — The old approach (`grep -v "flight:" | head -1`) found the most recent non-flight commit, not the parent of the first flight commit. Replaced with `git log --oneline --reverse | grep "flight:" | head -1` to find the first flight commit, then `git rev-parse "${FIRST_FLIGHT}^"` to get its parent. Also added guard for the edge case where all commits are flight commits. Applied to both `skills/flight-off/SKILL.md` (Step 4) and `skills/flight-on/SKILL.md` (Post-Flight Squash Reference).

### P1

3. **FIX 3: Squash commit count included all branches** — Removed `--all` flag from `git log` in Step 2 of flight-off so only current-branch flight commits are counted.
   - File: `skills/flight-off/SKILL.md`

4. **FIX 4: Missing airline codes** — Added F9 (Frontier Airlines, provider: none) and NK (Spirit Airlines, provider: ses) to `data/airline-codes.json` in alphabetical order. Both exist in airline-profiles.json but were missing from the codes file.
   - File: `data/airline-codes.json`

5. **FIX 5: No "already active" detection** — Added Step 0 to `/flight-on` that checks for existing `FLIGHT_MODE.md` before activation. Offers three choices: keep current session, restart with new settings, or run `/flight-off` first.
   - File: `skills/flight-on/SKILL.md`

6. **FIX 6: Preflight error handling** — Added `error` field check to Step 1 of `/flight-on`. When preflight script returns an error, the user is informed and directed to manual setup (Step 2).
   - File: `skills/flight-on/SKILL.md`

7. **FIX 7: `takeoff_time` always null** — Replaced `None` with `datetime.utcnow().isoformat() + "Z"` in the lookup script's route-data.json output. The dashboard now gets a real timestamp for elapsed time calculations.
   - File: `scripts/flight-on-lookup.sh`

### MEDIUM

8. **FIX 8: `block-direct-flight-mode.sh` overly broad match** — Changed from `grep -qF "FLIGHT_MODE.md"` (substring match) to `basename` comparison (exact filename match). Prevents false positives on paths like `FLIGHT_MODE.md.bak`.
   - File: `scripts/block-direct-flight-mode.sh`

## Test Results

- **Core tests (run-tests.sh):** 74/74 passed
- **Data validation (test-v2-data-validation.sh):** 25/25 passed
