# Iteration 2 — Backend Fixes

**Date:** 2026-03-18
**Scope:** 8 fixes across 6 files targeting reliability, portability, and security

## Changes

### FIX 1: context-monitor.sh — remove `set -e` (CRITICAL)
Changed `set -euo pipefail` to `set -uo pipefail`. The `-e` flag caused silent script exit on any non-zero command (e.g., grep returning no matches), breaking context tracking mid-session.

### FIX 2: flight-on-preflight.sh — JSON injection prevention (CRITICAL)
Replaced all 5 raw string interpolation calls (lines 17, 22, 27, 32, 57) with `jq -n` JSON construction. Previously, user input containing double quotes or backslashes would produce invalid JSON and break preflight orchestration.

### FIX 3: Ping portability — macOS vs Linux timeout units (HIGH)
- `context-monitor.sh`: Changed `-W 2` to platform-detected `-W 2000` (macOS) / `-W 2` (Linux)
- `flight-check.sh`: Changed `-W 5` to `-W 5000` (macOS) / `-W 5` (Linux)
macOS `ping -W` takes milliseconds; Linux takes seconds. Previous value of `-W 2` on macOS was a 2ms timeout that always failed.

### FIX 4: hooks.json — PostToolUse timeout increase (HIGH)
Changed context-monitor.sh hook timeout from 5 to 10 seconds. The script performs network calls (ping + curl) every 3rd invocation, which can exceed 5 seconds on degraded in-flight WiFi.

### FIX 5: context-monitor.sh — atomic state file writes (HIGH)
Both state file write locations (line 58 and line 158) now write to `${STATE_FILE}.tmp` first, then `mv` to the final path. Prevents corrupted reads if the hook is interrupted mid-write.

### FIX 6: Hash length consistency — macOS md5 truncation (HIGH)
- `context-monitor.sh`: Added `| cut -c1-12` to the macOS `md5` path
- `dashboard-server.sh`: Same change
Both scripts now produce consistent 12-char hashes on macOS and Linux, preventing state file / dashboard directory mismatches.
- `tests/run-tests.sh`: Updated test hash computation to match (required for T6.2-T6.4 threshold tests to find the seeded state file).

### FIX 7: dashboard-server.sh — remove `cd` before server start (HIGH)
Replaced `cd "$SERVE_DIR"` + `python3 -m http.server` with `python3 -m http.server --directory "$SERVE_DIR"`. Eliminates working directory side effect in the calling shell.

### FIX 8: flight-on-activate.sh — safe JSON output (HIGH)
Replaced raw heredoc string interpolation for the activation JSON output with `jq -n` construction. Prevents invalid JSON if file paths contain special characters.

## Files Modified
- `scripts/context-monitor.sh` (FIX 1, 3, 5, 6)
- `scripts/flight-on-preflight.sh` (FIX 2)
- `scripts/flight-check.sh` (FIX 3)
- `hooks/hooks.json` (FIX 4)
- `scripts/dashboard-server.sh` (FIX 6, 7)
- `scripts/flight-on-activate.sh` (FIX 8)
- `tests/run-tests.sh` (FIX 6 — test hash alignment)

## Test Results
- **Core tests:** 74/74 passed
- **Parse-flight tests:** 24/24 passed
- **Data validation tests:** 25/25 passed
