# QA Audit — Test Coverage Analysis (Iteration 1)

**Date:** 2026-03-18
**Auditor:** QA Lead
**Test Suite Version:** 173 tests across 8 test files (6 primary + 2 auxiliary)
**Status:** All 173 tests pass

---

## 1. Test Coverage Matrix

### Script x Test Category Matrix

| Script | Unit Tests | Data Validation | Integration | Error Handling | Boundary/Edge | Perf/Timing |
|--------|-----------|----------------|-------------|---------------|---------------|-------------|
| `stop-checkpoint.sh` | T5.1-T5.5 (5) | -- | live-simulation (D.1-D.3) | T8.6 (empty JSON) | T5.3 (no FLIGHT_MODE.md), T5.4 (loop guard), T5.5 (non-git dir) | -- |
| `context-monitor.sh` | T6.1, T6.5-T6.8 (5) | -- | live-simulation (C.1, C.3, E.5) | T8.7 (empty JSON) | T6.2-T6.4 (thresholds) | T6.7 (timeout <5s) |
| `parse-flight.sh` | PF.1-PF.14 (14) | -- | -- | PF.15 (empty input), PF.16 (gibberish) | PF.17 (case), PF.5/PF.19/PF.20 (digit-start codes), PF.6 (unknown code) | -- |
| `network-detect.sh` | ND.1-ND.5 (5) | ND.6-ND.10 (12) | -- | ND.5 (empty JSON) | -- | -- |
| `flight-check.sh` | FC.1-FC.6 (6) | FC.7-FC.16 (10) | -- | FC.18 (missing countries file) | -- | FC.17 (<30s timeout) |
| `flight-on-activate.sh` | -- | -- | live-simulation (B.1-B.2) | -- | -- | -- |
| `flight-on-lookup.sh` | -- | -- | -- | -- | -- | -- |
| `flight-on-preflight.sh` | -- | -- | -- | -- | -- | -- |
| `dashboard-server.sh` | -- | DB.1-DB.15 (HTML template only) | -- | -- | -- | -- |
| `block-direct-flight-mode.sh` | -- | -- | -- | -- | -- | -- |
| `measure-latency.sh` | -- | -- | -- | -- | -- | -- |
| `test-monitor.sh` | -- | -- | -- | -- | -- | -- |

### What IS Tested

**Structural tests (S.1-S.9, 17 tests in `run-tests.sh`):**
- plugin.json existence, validity, required fields (S.1-S.2)
- hooks.json existence, validity, Stop/PostToolUse events (S.3-S.4)
- Script executability for stop-checkpoint.sh and context-monitor.sh (S.5)
- SKILL.md frontmatter presence and required fields (S.6-S.7)
- Data file and template existence (S.8)
- Directory structure completeness (S.9)

**Stop hook (T5.1-T5.5, 5 tests in `run-tests.sh`):**
- Auto-checkpoint on session end with dirty working tree (T5.1)
- Clean tree produces no output (T5.2)
- No-op without FLIGHT_MODE.md (T5.3)
- Loop guard via stop_hook_active=true (T5.4)
- Graceful handling of non-git directory (T5.5)

**Context monitor (T6.1-T6.8, 8 tests in `run-tests.sh`):**
- Silent below threshold (T6.1)
- No-op without FLIGHT_MODE.md (T6.5)
- State file persistence and counter tracking (T6.6)
- Warning thresholds at ~45%, ~65%, ~85% (T6.2-T6.4)
- Timeout under 5 seconds (T6.7)
- Counter reset for fresh session (T6.8)

**Profile data (T7.1-T7.5, 13 tests in `run-tests.sh`):**
- Known carriers in profiles (T7.1)
- Rating scale values present (T7.2)
- UNKNOWN fallback (T7.3)
- Route patterns table (T7.4)
- Lookup table column structure (T7.5)

**Edge cases (T8.5-T8.12, 19 tests in `run-tests.sh`):**
- jq dependency and bad input handling (T8.5)
- Empty JSON input to stop hook and context monitor (T8.6-T8.7)
- CLAUDE_PLUGIN_ROOT references in SKILL.md and hooks.json (T8.8-T8.9)
- Protocol rules in flight-on skill (T8.10)
- Non-interactive squash in flight-off (T8.11)
- Calibration table completeness (T8.12)

**Parse flight (PF.1-PF.21, 24 tests in `test-v2-parse-flight.sh`):**
- Flight code parsing: CX884, UA123, BA 247, DL-456, 6E2145 (PF.1-PF.5)
- Unknown flight code handling (PF.6)
- Airline + route: CX HKG-LAX, DL JFK LAX, Cathay Pacific HKG-LAX (PF.7-PF.9)
- Airline name only: Cathay Pacific, United Airlines (PF.10-PF.11)
- Natural language: "cathay hong kong to los angeles" (PF.12)
- Airports only: HKG-LAX, HKG LAX (PF.13-PF.14)
- Edge cases: empty input, gibberish, case insensitivity, partial names, digit-start codes (PF.15-PF.20)
- Valid JSON for all inputs (PF.21)

**Network detect (ND.1-ND.10, 17 tests in `test-v2-network-detect.sh`):**
- Script exists, executable, valid JSON output, required fields (ND.1-ND.4)
- Empty JSON handling (ND.5)
- wifi-ssids.json structure: airline_patterns, airport_patterns arrays (ND.6-ND.8)
- Known SSID patterns present (ND.9)
- Airport patterns present (ND.10)

**Flight check (FC.1-FC.18, 18 tests in `test-v2-flight-check.sh`):**
- Script basics: exists, valid JSON, required fields (FC.1-FC.3)
- Field value validation: verdict enum, boolean types (FC.4-FC.6)
- supported-countries.json structure and content (FC.7-FC.13)
- provider-egress.json structure and content (FC.14-FC.16)
- Runtime: completes <30s, handles missing data file (FC.17-FC.18)

**Data validation (DV.1-DV.25, 25 tests in `test-v2-data-validation.sh`):**
- airline-codes.json: valid JSON, 60+ entries, required fields, valid providers, known airlines (DV.1-DV.5)
- airport-codes.json: valid JSON, 90+ entries, required fields, lat/lon ranges, known airports (DV.6-DV.11)
- route-corridors.json: valid JSON, 10 corridors, required fields, waypoint structure, signal ranges, sorting, start/end conditions (DV.12-DV.20)
- Other data files valid JSON (DV.21-DV.23)
- Cross-reference: airline countries vs airport/country data, corridor examples vs airport codes (DV.24-DV.25)

**Dashboard (DB.1-DB.15, 15 tests in `test-v2-dashboard.sh`):**
- File exists, valid HTML structure (DB.1-DB.2)
- Required DOM elements: flightCode, routeStr, apiStatus, elapsedTime (DB.3)
- Timeline SVG, latency SVG, drop log table (DB.4-DB.6)
- Data fetching: route-data.json, live-data.json, setInterval (DB.7-DB.9)
- Interactive features: tooltip, stale banner (DB.10-DB.11)
- Styling: JetBrains Mono, dark theme, file size, signal color function (DB.12-DB.15)

**Live simulation (A.1-F.5, 20 tests in `live-simulation.sh`):**
- Pre-activation no-ops (A.1-A.2)
- Activation: FLIGHT_MODE.md, .flight-state.md creation, gitignore (B.1-B.3)
- Work session: tool call tracking, flight: prefix, context monitor silence, checkpoint (C.1-C.4)
- WiFi drop: stop hook auto-checkpoint, approve JSON output (D.1-D.3)
- Recovery: file persistence, recovery instructions, resume point, context reset (E.1-E.5)
- Deactivation: commit count, squash, archive, cleanup, hooks return to no-op (F.1-F.5)

### What is NOT Tested

**`flight-on-activate.sh` (0 dedicated unit tests):**
- No test validates the script directly with controlled input and inspected output
- Only tested indirectly via live-simulation.sh (B.1-B.2) which manually creates files
- Missing: validation of generated FLIGHT_MODE.md content fields, .flight-state.md content, edge cases for missing/null input fields, behavior when cwd is read-only, behavior when cwd already has FLIGHT_MODE.md

**`flight-on-lookup.sh` (0 tests):**
- No test invokes this script at all
- Missing: profile lookup for known airline codes, variant airline handling (UA_starlink vs UA_legacy), corridor matching by exact example, corridor matching by proximity, unknown airline fallback, missing data files, route-data.json write verification, domestic vs long-haul rating selection, calibration table selection, haversine distance edge cases

**`flight-on-preflight.sh` (0 tests):**
- No test invokes the orchestrator
- Missing: end-to-end flow with all sub-scripts, partial failure scenarios (one sub-script fails), missing field detection logic, ready vs not-ready determination, JSON assembly

**`dashboard-server.sh` (0 behavioral tests):**
- The DB.* tests only validate the HTML template as a static file
- Missing: start command creates serve directory, copies HTML, starts Python server; stop command kills process, removes directory; status command reports running/not_running; write-route and write-live commands update JSON files; already_running detection; port conflict handling; stale PID file handling; unknown command error

**`block-direct-flight-mode.sh` (0 tests):**
- Not tested at all
- Missing: blocks Write to FLIGHT_MODE.md paths, allows Write to other paths, handles missing file_path in input, handles various path formats (absolute, relative, nested)

**`measure-latency.sh` (0 tests):**
- Not tested at all
- Missing: --header flag outputs CSV header, data output format, timeout handling for ping/curl/dig, network failure graceful handling

**`test-monitor.sh` (0 tests):**
- Utility script, lower priority, but no tests exist

**Context monitor latency measurement path (lines 87-181 of context-monitor.sh):**
- The "every 3rd call" latency measurement logic is completely untested
- Missing: ping measurement, HTTP latency measurement, API status determination (GO/CAUTION/BLOCKED/OFFLINE), drop detection logic, measurements array accumulation (last 20), drops array accumulation (last 10), live-data.json writing to dashboard directory, state file update with measurements/drops

**Stop hook staged files behavior:**
- Only tests with `git add -u` — does not verify which files get staged
- Missing: test that untracked files are NOT staged (only modified tracked files)
- Missing: test with both modified and untracked files to verify selective staging

---

## 2. Missing Test Categories

### 2a. Integration Tests (Multi-Script Flows)

**Entirely absent.** The live-simulation.sh comes closest but manually creates files rather than calling the actual scripts in sequence.

Missing integration tests:
- `parse-flight.sh` output piped into `flight-on-lookup.sh` — does the JSON transfer correctly?
- `flight-on-preflight.sh` calling all sub-scripts and assembling output — end-to-end
- `flight-on-lookup.sh` writing `route-data.json` + `context-monitor.sh` writing `live-data.json` — do they coexist correctly in the dashboard serve directory?
- `dashboard-server.sh start` followed by `context-monitor.sh` latency writes — does the dashboard serve directory get populated?
- `flight-on-activate.sh` then `stop-checkpoint.sh` — full activation to auto-checkpoint

### 2b. End-to-End Tests (Full Lifecycle)

The `live-simulation.sh` is close but has critical gaps:
- Does NOT call `flight-on-activate.sh` (manually creates FLIGHT_MODE.md)
- Does NOT call `flight-on-lookup.sh`
- Does NOT call `flight-on-preflight.sh`
- Does NOT start/stop the dashboard server
- Does NOT verify the squash logic with real git history
- Does NOT verify deactivation cleanup (archive, FLIGHT_MODE.md removal)

### 2c. Regression Tests for Known Edge Cases

No regression test file exists. Known edge cases from code analysis that lack tests:
- `parse-flight.sh`: Three-letter ICAO codes (e.g., "AAL123") — sorted longest-first matching
- `flight-on-lookup.sh`: Variant airline selection (most conservative rating) — critical logic at lines 62-76
- `context-monitor.sh`: Race condition if state file is read/written simultaneously by two processes
- `flight-check.sh`: When curl returns empty but exit code 0

### 2d. Error Injection Tests

**Zero tests for tool dependency failures:**
- What happens when `python3` is not installed? (parse-flight.sh, network-detect.sh, flight-check.sh, flight-on-lookup.sh all require it)
- What happens when `jq` is not installed? (every hook script requires it)
- What happens when `git` operations fail (locked repo, disk full)?
- What happens when `curl` times out or returns garbage?
- What happens when `ping` is blocked by firewall?
- What happens when `/tmp` is not writable?
- What happens when data JSON files are valid JSON but wrong schema (e.g., airline-codes.json missing the "name" field)?
- What happens when python3 is installed but a required module is missing?

### 2e. Concurrent Session Tests

**Zero tests.** Critical gap because:
- Multiple Claude sessions in different repos share `/tmp/flight-mode-*` namespace
- State files are keyed by directory hash — but no test verifies hash isolation
- No test verifies two simultaneous sessions don't corrupt each other's state files
- Dashboard server uses a fixed default port (8234) — no test for port conflicts between sessions

### 2f. File System Edge Cases

**Zero tests for:**
- Read-only working directory (activate script writes to CWD)
- Long file paths (>PATH_MAX for state file path construction)
- Directory names with spaces in `WORKDIR` (affects hash computation and state file paths)
- Working directory path containing special characters (quotes, backticks)
- /tmp filesystem full (state file creation fails)
- Symlinked working directories (hash would differ from resolved path)

### 2g. Dashboard Integration Tests

**Zero.** The `test-v2-dashboard.sh` tests only validate the HTML template as a static file (string matching). Missing:
- Start server, verify HTTP 200 at localhost:8234
- Write route-data.json, fetch from server, verify content
- Write live-data.json, fetch from server, verify content
- Start two dashboards on different ports — verify isolation
- Stop dashboard — verify port is freed, directory cleaned up
- Stale PID handling — server died but PID file remains

---

## 3. Test Quality Assessment

### 3a. Assertion Specificity

**Mixed quality.** Some tests check exit codes only, others check output content.

**Good examples (specific assertions):**
- PF.1 checks 5 fields: airline_code, airline_name, parsed_from, confidence, needs_route
- T6.2-T6.4 check for specific warning text substrings
- DV.24-DV.25 cross-reference validation with Python scripts

**Weak examples (exit code only):**
- T5.5 (non-git dir): only checks exit code 0 — does not verify that no commit was created or that no error message was emitted to stderr
- T8.6: stop hook with empty JSON — only checks rc=0, does not verify no commit was created
- T8.7: context monitor with empty JSON — only checks rc=0, does not verify no state file was created
- ND.5: empty JSON input — only checks rc=0, does not verify output fields
- FC.18: missing countries file — only checks rc=0, does not verify warning field is set

### 3b. Failure Message Quality

**Generally good.** Most tests include diagnostic output in failure messages:
- `fail "PF.1 CX884" "ac=$AC an=$AN pf=$PF cf=$CF nr=$NR"` — shows all fields
- `fail "T5.1 auto-checkpoint commit" "last msg: $LAST_MSG"` — shows actual value

**Could be improved:**
- T6.2-T6.4: Failure message shows `output: $OUTPUT` but doesn't show the expected text pattern, making it harder to diagnose near-misses
- T5.2: `fail "T5.2 clean tree" "rc=$RC, output=$OUTPUT"` — good but would benefit from showing git log -1 to see if an unwanted commit was made

### 3c. Test Isolation

**Moderate concern.** Several tests share state:

**Problems found:**
1. **`run-tests.sh` T5 and T6 share `$TEST_DIR`** — T6 tests depend on the FLIGHT_MODE.md created in T5 (line 232: `echo "# Flight Mode Active" > "$TEST_DIR/FLIGHT_MODE.md"`). If T5 tests fail and leave the directory in an unexpected state, T6 tests may be affected.

2. **T6.2-T6.4 threshold tests manipulate a shared state file** at `$REAL_STATE_DIR/context.json` (lines 292-318). The tests seed the state file with specific counter values. If the hash computation fails or produces an unexpected value, all three tests would fail silently.

3. **`/tmp/flight-mode-*` cleanup is done manually** (lines 229, 257, 277, 333-339, 483). Between test groups, cleanup happens with `rm -rf /tmp/flight-mode-* 2>/dev/null || true`. If a test creates a state directory that doesn't match the glob (unlikely but possible), it persists.

4. **`live-simulation.sh` uses `cd "$TEST_DIR"`** (line 21) — changes the working directory for the entire test runner, which works but means any test after a failure could be in an unexpected directory.

### 3d. Cleanup Reliability

**Good but imperfect:**

- `run-tests.sh` uses `trap cleanup_t5 EXIT` (line 142) for the test directory. However, this trap only cleans up `$TEST_DIR`, not the `/tmp/flight-mode-*` state directories. The explicit cleanup on line 483 handles this, but if the script exits early (e.g., from `set -e`), state files may persist.

- `live-simulation.sh` cleans up properly at the end (lines 333-334) but uses no trap. If the test script is killed (Ctrl+C), `/tmp/flight-mode-*` files and the test git repo persist.

- `test-v2-flight-check.sh` creates a temporary plugin directory (line 236) and cleans it up immediately after (line 242). This is well-scoped.

### 3e. Leftover State

**Risk of leaving `/tmp/flight-mode-*` files:**

Tests create state files under `/tmp/flight-mode-${DIR_HASH}/` (context-monitor tests) and `/tmp/flight-mode-dashboard-${DIR_HASH}/` (dashboard tests, though not currently tested). These are cleaned up by explicit `rm -rf` calls, but:
- If a test file is run individually and interrupted, cleanup doesn't happen
- `run-tests.sh` cleanup at line 483 uses glob `rm -rf /tmp/flight-mode-*` which would also delete state files from OTHER active flight mode sessions (if any)
- `live-simulation.sh` has the same broad cleanup at line 334

---

## 4. Critical Untested Paths (Risk-Ordered)

### 4.1. CRITICAL: The squash logic in `/flight-off` (`git reset --soft`)

**Risk: HIGH** — Data loss if the squash command identifies the wrong "before flight" commit.

The squash approach (lines 68-76 of `skills/flight-off/SKILL.md`) uses:
```bash
BEFORE_FLIGHT=$(git log --oneline | grep -v "flight:" | head -1 | cut -d' ' -f1)
git reset --soft $BEFORE_FLIGHT
```

**Problems not tested:**
1. `grep -v "flight:"` matches the FIRST line that does NOT contain "flight:" — this is the most recent non-flight commit, which is correct only if ALL flight commits are contiguous and most recent. If there are interleaved non-flight commits, this command would reset to the wrong point.
2. The live-simulation.sh tests a squash (lines 277-289) but uses a simplified approach that manually identifies `$BEFORE_FLIGHT`. It does NOT test the actual command from the SKILL.md.
3. No test verifies behavior when ALL commits have "flight:" prefix (grep -v returns empty, head -1 is empty, git reset --soft with empty arg).
4. No test verifies behavior with merge commits in the history.

### 4.2. CRITICAL: `flight-on-preflight.sh` — Zero Tests

**Risk: HIGH** — This is the orchestrator that runs during `/flight-on`. If it fails, the activation flow breaks.

Untested paths:
- Sub-script failures (any of the 4 scripts could fail; fallback JSON literals at lines 18, 23, 28, 33)
- JSON assembly via Python (line 69-85) — if Python fails, fallback is a bare error string
- `ready` determination logic (lines 42-51)
- Dashboard directory extraction for lookup input (line 56)

### 4.3. CRITICAL: `flight-on-lookup.sh` — Zero Tests

**Risk: HIGH** — This script determines the WiFi rating, calibration settings, and corridor data. Wrong output means wrong checkpoint intervals.

Untested paths:
- Variant airline handling (lines 64-76 of the Python block): selects most conservative variant. If the ranking logic is wrong, users get overly optimistic settings.
- Corridor matching by proximity (lines 112-134): haversine distance calculation, forward vs reverse matching
- Domestic vs long-haul determination (lines 153-159): `domestic_max` threshold from profiles
- Null handling in variant profiles (lines 155-158): `or` chains for rating/stable_window
- Dashboard route-data.json write (lines 182-198)
- Missing data files gracefully handled

### 4.4. HIGH: Context monitor latency measurement (lines 87-181 of `context-monitor.sh`)

**Risk: HIGH** — This is the code that detects drops and writes live dashboard data. Completely untested.

Untested paths:
- Ping measurement parsing (lines 97-101): regex to extract `time=X.Y` from ping output
- HTTP latency measurement (lines 105-109): curl time_total parsing
- API status logic (lines 113-125): GO/CAUTION/BLOCKED/OFFLINE determination
- Drop detection (lines 128-133): ping failure or >5000ms latency
- Measurements array accumulation with 20-item window (line 141)
- Drops array accumulation with 10-item window (line 151)
- State file update with measurements/drops (lines 155-159)
- live-data.json write to dashboard directory (lines 162-180)

### 4.5. HIGH: `block-direct-flight-mode.sh` — Zero Tests

**Risk: MEDIUM** — PreToolUse hook that prevents direct writes to FLIGHT_MODE.md. If broken, the integrity enforcement is gone.

Untested paths:
- FLIGHT_MODE.md path detection (line 7): `grep -qF "FLIGHT_MODE.md"`
- Deny output format correctness (lines 8-16): JSON with hookSpecificOutput
- Non-FLIGHT_MODE.md paths should pass through silently (line 20)
- Path variants: absolute paths, relative paths, paths with FLIGHT_MODE.md as substring in directory name

### 4.6. HIGH: `flight-on-activate.sh` — Zero Dedicated Tests

**Risk: MEDIUM** — Writes both FLIGHT_MODE.md and .flight-state.md. Only tested indirectly via live-simulation which creates files manually.

Untested paths:
- Correct field substitution in FLIGHT_MODE.md template (lines 41-63)
- Correct field substitution in .flight-state.md template (lines 65-88)
- Missing/null input fields (what if rating is empty?)
- Weak zone line conditional (lines 36-39): only included when WZ_START and WZ_END are both non-empty
- JSON output format (lines 90-96)
- Behavior when CWD already contains FLIGHT_MODE.md (overwrite vs error?)
- Behavior when CWD is not writable

### 4.7. MEDIUM: `dashboard-server.sh` — Zero Behavioral Tests

**Risk: MEDIUM** — Server lifecycle management. If start/stop breaks, dashboard is unavailable or orphaned processes remain.

Untested paths:
- `cmd_start`: directory creation, HTML copy, server launch, PID file write, already-running detection
- `cmd_stop`: process kill, force kill timeout, directory cleanup, stale PID handling
- `cmd_status`: running vs not_running detection
- `cmd_write_route` and `cmd_write_live`: file writing, error when dashboard not running
- Unknown command error handling (line 166)
- Port already in use scenario

### 4.8. MEDIUM: `measure-latency.sh` — Zero Tests

**Risk: LOW** — Standalone utility, not in the critical path. But CSV format errors could corrupt measurement data.

### 4.9. LOW: hooks.json matcher patterns

The hooks.json PostToolUse matcher (line 29) is `"Read|Edit|Write|Bash|Grep|Glob"`. No test verifies that the matcher pattern correctly matches/excludes tool names. The PreToolUse matcher (line 17) is `"Write"` only.

---

## 5. Test Infrastructure Assessment

### 5a. Test Runner Robustness

**`run-tests.sh`:**
- Uses `set -uo pipefail` but NOT `set -e` — correct for a test runner that needs to continue after failures
- Exit code is `$FAIL` count — standard and useful for CI
- Color output works in terminals but would need `--no-color` flag for CI piping
- No TAP (Test Anything Protocol) output — harder to integrate with CI test reporters
- No test filtering (cannot run a subset of tests)
- No parallel execution

**Individual test files (`test-v2-*.sh`):**
- Each uses the same boilerplate (pass/fail/skip/section functions) — duplicated ~25 lines per file
- Could be extracted to a shared test-lib.sh
- Each exits with `$FAIL` count — consistent

### 5b. CI Readiness

**Mostly CI-ready with caveats:**

1. **Network-dependent tests will fail in CI:**
   - `test-v2-flight-check.sh` FC.2-FC.6 depend on live network (curl to api.anthropic.com, ipinfo.io)
   - `test-v2-flight-check.sh` FC.17 timing test depends on network latency
   - `test-v2-network-detect.sh` ND.2-ND.4 run the actual network-detect.sh which tries to read WiFi SSID
   - `context-monitor.sh` latency measurement (if tested) requires ping and curl

2. **macOS-specific commands will fail on Linux CI:**
   - `network-detect.sh` uses `/System/Library/PrivateFrameworks/Apple80211.framework/...` (line 69) and `networksetup` (line 74) — macOS only
   - `md5` command (used in context-monitor.sh line 19, dashboard-server.sh line 26) — macOS only (Linux uses `md5sum`). The scripts handle both, but tests don't verify the Linux path.
   - `ping -W 2` flag semantics differ between macOS and Linux (macOS: -W is wait time in ms on some versions, seconds on others)

3. **Test dependencies not declared:**
   - Requires: bash, jq, python3, git, grep, awk, sed, curl, ping, host/nslookup
   - No prerequisite check at the top of the test runner (individual tests check some deps like PF.0c-PF.0d)

4. **No CI configuration file** exists (.github/workflows/*.yml, etc.)

### 5c. macOS vs Linux Compatibility

Scripts that would fail on Linux:
- `network-detect.sh`: WiFi SSID detection is macOS-only (`airport -I`, `networksetup`)
- `measure-latency.sh`: uses `dig` (may not be available on minimal Linux images)

Scripts with macOS/Linux divergence handled:
- Hash computation: `md5` (macOS) vs `md5sum` (Linux) vs `cksum` (fallback) — covered in context-monitor.sh, dashboard-server.sh
- Ping output parsing: both use `tail -1 | awk -F'/' '{print $5}'` — works on both platforms for the summary line

### 5d. Test Timing/Flakiness Assessment

**Potential flaky tests:**

1. **FC.17 (timeout <30s):** Depends on actual network conditions. If the test environment has slow DNS or the API is slow, this test could flake. On fast networks it passes in <2s; on airplane WiFi it might take 15-20s and still pass.

2. **T6.7 (timeout <5s):** Currently measures wall-clock time with `date +%s` which has 1-second resolution. A test that takes 4.9s could show as 4s or 5s depending on timing. Low risk but not deterministic.

3. **FC.2-FC.6 (network-dependent):** Will fail or be skipped without network. The test handles timeout (line 52-53) but relies on specific HTTP responses from api.anthropic.com.

4. **T6.2-T6.4 (threshold tests):** These seed state files with specific counter values and check for warning text. Fragile if the threshold formula changes — the seeded values (26, 38, 50) are tightly coupled to the formula `(tool_calls * 2.5 + lines_read * 0.01) / 1.5`.

---

## 6. Proposed Test Plan — Top 20 Missing Tests

Ordered by risk and impact. Each test includes input, expected behavior, and which file it should be added to.

### Test 1: `flight-on-lookup.sh` — Basic Airline Profile Lookup
**Priority: P0 (Critical)**
**File:** New `tests/test-v2-lookup.sh`
```
Input: {"airline_code":"CX","origin":"HKG","destination":"LAX","plugin_dir":"$PLUGIN_DIR"}
Expected: JSON with rating containing "USABLE" or "GOOD", corridor containing a valid corridor ID,
          duration_hours > 0, waypoints array non-empty, calibration object with batch_size/checkpoint_interval
Verify: airline_name = "Cathay Pacific", provider = "viasat" or known value
```

### Test 2: `flight-on-lookup.sh` — Variant Airline Selection (Most Conservative)
**Priority: P0 (Critical)**
**File:** `tests/test-v2-lookup.sh`
```
Input: {"airline_code":"UA","origin":"SFO","destination":"ORD","plugin_dir":"$PLUGIN_DIR"}
Expected: JSON with rating NOT "EXCELLENT" (should pick UA_legacy which is "USABLE", not UA_starlink
          which is "EXCELLENT"). The variant selection should choose the most conservative profile.
Verify: rating = "USABLE" (worst of the two variants for domestic)
```

### Test 3: `flight-on-lookup.sh` — Unknown Airline Fallback
**Priority: P0 (Critical)**
**File:** `tests/test-v2-lookup.sh`
```
Input: {"airline_code":"ZZ","origin":"JFK","destination":"LAX","plugin_dir":"$PLUGIN_DIR"}
Expected: JSON with default profile values, rating from default profile, calibration from UNKNOWN key
Verify: Output is valid JSON with all required fields, no crash
```

### Test 4: `flight-on-preflight.sh` — Full Orchestration (Happy Path)
**Priority: P0 (Critical)**
**File:** New `tests/test-v2-preflight.sh`
```
Input: $1 = "CX884", $2 = "$PLUGIN_DIR"
Expected: JSON with parse, network, api, dashboard, lookup sections. ready = depends on whether
          CX884 provides a route (it doesn't — needs_route=true → ready=false, missing=["route"])
Verify: parse.airline_code = "CX", parse.confidence = "high", missing = ["route"]
```

### Test 5: `flight-on-preflight.sh` — Full Input With Route
**Priority: P0 (Critical)**
**File:** `tests/test-v2-preflight.sh`
```
Input: $1 = "CX HKG-LAX", $2 = "$PLUGIN_DIR"
Expected: JSON with ready = true, missing = [], lookup != null
Verify: parse.airline_code = "CX", parse.origin = "HKG", parse.destination = "LAX", lookup object present
```

### Test 6: `flight-on-activate.sh` — FLIGHT_MODE.md Content Verification
**Priority: P1 (High)**
**File:** New `tests/test-v2-activate.sh`
```
Setup: Create temp git repo, cd into it
Input: {"airline_code":"CX","airline_name":"Cathay Pacific","origin":"HKG","destination":"LAX",
        "provider":"viasat","rating":"USABLE","stable_window":"20-40","duration_hours":12,
        "api_verdict":"GO","egress_country":"US","dashboard_url":"http://localhost:8234",
        "calibration":{"batch_size":"1-2","checkpoint_interval":"2-3","commit_interval":"2-3"},
        "cwd":"$TEMP_DIR"}
Expected: FLIGHT_MODE.md created with correct field values, .flight-state.md created,
          JSON output with status=activated
Verify: grep "Cathay Pacific" FLIGHT_MODE.md, grep "HKG -> LAX" FLIGHT_MODE.md,
        grep "USABLE" FLIGHT_MODE.md, grep "viasat" FLIGHT_MODE.md
```

### Test 7: `flight-on-activate.sh` — Weak Zone Conditional
**Priority: P1 (High)**
**File:** `tests/test-v2-activate.sh`
```
Input A: {"weak_zone":{"start_hour":4,"end_hour":8,"reason":"mid-Pacific"},...}
Expected A: FLIGHT_MODE.md contains "Weak Zone: Hours 4-8"

Input B: {} (no weak_zone fields)
Expected B: FLIGHT_MODE.md does NOT contain "Weak Zone"
```

### Test 8: `block-direct-flight-mode.sh` — Blocks FLIGHT_MODE.md Write
**Priority: P1 (High)**
**File:** New `tests/test-v2-block-direct.sh`
```
Input: {"tool_input":{"file_path":"/some/path/FLIGHT_MODE.md"}}
Expected: JSON output with permissionDecision = "deny", exit code 0

Input: {"tool_input":{"file_path":"/some/path/other-file.txt"}}
Expected: Empty output, exit code 0

Input: {"tool_input":{"file_path":"/some/FLIGHT_MODE.md.bak"}}
Expected: JSON output with permissionDecision = "deny" (grep -qF matches substring)
Note: This is potentially a BUG — "FLIGHT_MODE.md.bak" contains "FLIGHT_MODE.md" as a substring
      and would be blocked. Test documents this behavior.
```

### Test 9: Context Monitor Latency Measurement — GO Status
**Priority: P1 (High)**
**File:** Add to `tests/run-tests.sh` as T6.9 or new file
```
Setup: Create FLIGHT_MODE.md, seed state with tool_calls=2 (so 3rd call triggers measurement)
Input: {"cwd":"$TEST_DIR","tool_name":"Bash","tool_output":"ok"}
Expected: State file updated with measurements array containing at least 1 entry,
          each entry has timestamp, ping_ms, http_ms fields
Verify: jq '.measurements | length' > 0, jq '.measurements[0].timestamp' is ISO format
Note: Requires network access — mark as SKIP if offline
```

### Test 10: Dashboard Server Start/Stop Lifecycle
**Priority: P1 (High)**
**File:** New `tests/test-v2-dashboard-server.sh`
```
Test A (start):
  Input: {"command":"start","cwd":"$TEMP_DIR","plugin_dir":"$PLUGIN_DIR"}
  Expected: JSON with status="started", url contains ":8234", pid > 0, serve_dir path
  Verify: curl http://localhost:8234 returns 200, PID file exists and process is alive

Test B (status):
  Input: {"command":"status","cwd":"$TEMP_DIR","plugin_dir":"$PLUGIN_DIR"}
  Expected: JSON with status="running"

Test C (stop):
  Input: {"command":"stop","cwd":"$TEMP_DIR","plugin_dir":"$PLUGIN_DIR"}
  Expected: JSON with status="stopped", process is dead, serve directory removed

Test D (already running):
  Run start twice with same cwd
  Expected: Second call returns status="already_running", same PID

Cleanup: Ensure server is stopped after test
```

### Test 11: Squash Logic Correctness (from `/flight-off`)
**Priority: P0 (Critical)**
**File:** New `tests/test-v2-squash.sh`
```
Setup: Create git repo with history:
  commit A: "initial"
  commit B: "feat: base feature"
  commit C: "flight: task 1"
  commit D: "flight: task 2"
  commit E: "flight: task 3"

Test A (contiguous flight commits):
  Run: BEFORE_FLIGHT=$(git log --oneline | grep -v "flight:" | head -1 | cut -d' ' -f1)
       git reset --soft $BEFORE_FLIGHT
       git commit -m "feat: squashed"
  Expected: 3 commits remain (A, B, "feat: squashed"), all flight changes preserved in new commit

Test B (interleaved non-flight commit):
  History: A, "flight: 1", "fix: unrelated", "flight: 2"
  Run same squash command
  Expected: DANGEROUS — grep -v "flight:" picks "fix: unrelated", losing "flight: 1"
  Document: This is a known limitation/bug in the squash logic

Test C (all commits are flight commits):
  History: "flight: 1", "flight: 2"
  Run: grep -v "flight:" returns nothing
  Expected: head -1 returns empty, git reset --soft "" fails
  Document: Edge case — needs guard
```

### Test 12: `flight-on-lookup.sh` — Corridor Matching by Proximity
**Priority: P1 (High)**
**File:** `tests/test-v2-lookup.sh`
```
Input: {"airline_code":"QF","origin":"SYD","destination":"LAX","plugin_dir":"$PLUGIN_DIR"}
Expected: Corridor matched (transpacific or similar), waypoints array non-empty,
          duration_hours > 10 (long-haul route)
Verify: corridor != "unknown", output valid JSON
```

### Test 13: `flight-on-lookup.sh` — Domestic vs Long-Haul Rating Selection
**Priority: P1 (High)**
**File:** `tests/test-v2-lookup.sh`
```
Input A (domestic): {"airline_code":"DL","origin":"JFK","destination":"LAX","plugin_dir":"$PLUGIN_DIR"}
Expected: rating = "GOOD" (Delta domestic rating from profiles)

Input B (long-haul): {"airline_code":"DL","origin":"JFK","destination":"LHR","plugin_dir":"$PLUGIN_DIR"}
Expected: rating = "USABLE" (Delta long-haul rating from profiles)
```

### Test 14: `parse-flight.sh` — Three-Letter IATA Code Handling
**Priority: P2 (Medium)**
**File:** `tests/test-v2-parse-flight.sh`
```
Input: "SQ321" (Singapore Airlines)
Expected: airline_code = "SQ", airline_name = "Singapore Airlines", confidence = "high"

Input: "QF1" (Qantas, single-digit flight)
Expected: airline_code = "QF", airline_name = "Qantas"
```

### Test 15: Context Monitor — State File Isolation Between Projects
**Priority: P1 (High)**
**File:** Add to `tests/run-tests.sh` as T6.10
```
Setup: Create two temp directories DIR_A and DIR_B, each with FLIGHT_MODE.md
Run: 5 calls with cwd=DIR_A, then 3 calls with cwd=DIR_B
Expected: DIR_A state file shows tool_calls=5, DIR_B state file shows tool_calls=3
          (separate state files, no cross-contamination)
```

### Test 16: Stop Hook — Untracked Files NOT Staged
**Priority: P1 (High)**
**File:** Add to `tests/run-tests.sh` as T5.6
```
Setup: Git repo with committed file, create NEW untracked file, modify committed file
Run: stop-checkpoint.sh
Expected: Commit contains only the modified tracked file. Untracked file is NOT in the commit.
Verify: git show --stat HEAD -- does not include the untracked filename
```

### Test 17: `flight-on-activate.sh` — Missing Input Fields
**Priority: P2 (Medium)**
**File:** `tests/test-v2-activate.sh`
```
Input: {"cwd":"$TEMP_DIR"} (minimal — all other fields missing)
Expected: FLIGHT_MODE.md created with default values ("??", "Unknown", etc.), no crash
Verify: File exists, contains "# Flight Mode Active", JSON output has status=activated
```

### Test 18: `network-detect.sh` — SSID Classification Logic
**Priority: P2 (Medium)**
**File:** `tests/test-v2-network-detect.sh` (new section)
```
Note: Cannot control actual WiFi SSID, but can test the Python classification logic directly.
Approach: Extract the Python block, feed it test SSIDs via environment variables.

Test: SSID_VAR="gogoinflight" → type=airline, provider from data file
Test: SSID_VAR="Free Airport WiFi" → type=airport
Test: SSID_VAR="MyHomeNetwork" → type=other, confidence=low
```

### Test 19: `flight-check.sh` — Offline Verdict When DNS Fails
**Priority: P2 (Medium)**
**File:** Add to `tests/test-v2-flight-check.sh`
```
Note: Difficult to simulate DNS failure in a test. Alternative: verify that the script's
      verdict logic produces correct output for known input combinations.
Approach: Test the verdict determination logic by examining output when run on known networks.
          Or: create a mock wrapper that overrides host/nslookup to simulate DNS failure.
```

### Test 20: `flight-on-lookup.sh` — route-data.json Written to Dashboard Dir
**Priority: P1 (High)**
**File:** `tests/test-v2-lookup.sh`
```
Setup: Create temp dashboard directory
Input: {"airline_code":"CX","origin":"HKG","destination":"LAX","plugin_dir":"$PLUGIN_DIR",
        "dashboard_dir":"$TEMP_DASH_DIR"}
Expected: $TEMP_DASH_DIR/route-data.json exists and is valid JSON
Verify: jq '.flight' = "CX", jq '.route' = "HKG-LAX", jq '.rating' is a valid rating string,
        jq '.waypoints | length' > 0 (if corridor matched)
```

---

## Appendix A: Test File to Script Mapping

| Script | Primary Test File | Test Count | Coverage Grade |
|--------|------------------|------------|----------------|
| `stop-checkpoint.sh` | `run-tests.sh` T5.1-T5.5 | 5 + 3 edge + 3 sim | B (core paths covered, edges weak) |
| `context-monitor.sh` | `run-tests.sh` T6.1-T6.8 | 8 + 1 edge + 3 sim | C (threshold logic tested, latency path 0%) |
| `parse-flight.sh` | `test-v2-parse-flight.sh` | 24 | A- (good coverage, missing some edge cases) |
| `network-detect.sh` | `test-v2-network-detect.sh` | 17 | B- (data validation good, behavior undertested) |
| `flight-check.sh` | `test-v2-flight-check.sh` | 18 | B- (data validation good, runtime network-dependent) |
| `flight-on-activate.sh` | none (indirect only) | 0 | F |
| `flight-on-lookup.sh` | none | 0 | F |
| `flight-on-preflight.sh` | none | 0 | F |
| `dashboard-server.sh` | `test-v2-dashboard.sh` (template only) | 15 (template) | F (server logic 0%) |
| `block-direct-flight-mode.sh` | none | 0 | F |
| `measure-latency.sh` | none | 0 | F |
| Data files | `test-v2-data-validation.sh` | 25 | A (thorough cross-validation) |
| Plugin structure | `run-tests.sh` S.* | 17 | A |
| Full lifecycle | `live-simulation.sh` | 20 | B (good flow, but uses manual file creation not actual scripts) |

### Overall Coverage Estimate

- **Lines of bash tested:** ~45% of total script lines
- **Critical paths tested:** ~35% (3 of 8 critical scripts have zero coverage)
- **Data validation:** ~95% (strongest area)
- **Integration/E2E:** ~15% (live-simulation is partial)
- **Error handling:** ~10% (mostly just empty JSON)

---

## Appendix B: Specific Line References

| File | Lines | What's Untested |
|------|-------|-----------------|
| `context-monitor.sh` | 87-181 | Entire latency measurement block: ping, curl timing, status determination, drop detection, measurements/drops arrays, live-data.json write |
| `flight-on-lookup.sh` | 24-201 | Entire script: all Python logic including profile lookup, variant selection, corridor matching, haversine, rating determination, calibration, route-data.json write |
| `flight-on-preflight.sh` | 1-85 | Entire script: orchestration, sub-script invocation, ready/missing logic, JSON assembly |
| `flight-on-activate.sh` | 1-96 | Entire script: field extraction, template rendering, weak zone conditional, file writes |
| `dashboard-server.sh` | 49-170 | All commands: start (dir creation, server launch, PID), stop (kill, cleanup), status, write-route, write-live, unknown command |
| `block-direct-flight-mode.sh` | 1-21 | Entire script: path matching, deny output, passthrough |
| `stop-checkpoint.sh` | 26-27 | Tracked-only change detection (`grep -v '^??'`): verified implicitly but not explicitly tested with mixed tracked/untracked changes |
