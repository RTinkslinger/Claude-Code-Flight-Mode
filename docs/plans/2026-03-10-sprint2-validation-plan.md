# Sprint 2: Validation Plan

**Date:** 2026-03-10
**Sprint Goal:** Validate everything built in Sprint 1 before shipping. Zero new features.
**Principle:** The plugin's purpose is reliability — hold ourselves to the same standard.

---

## Context

Sprint 1 delivered a complete Flight Mode v2.0.0 plugin: core plugin (layered protocol, hooks, auto-checkpoint), V2 features (flight parsing, network detection, API geo-checking, live dashboard, route corridors), and a deterministic two-phase orchestrator redesign. 173 tests pass. But:

- The deterministic redesign (`!`command`` injection) was never invoked as a live skill
- The installed plugin cache may be stale (jetsam crash before re-install)
- 9 Notion roadmap items sit in "Verifying" with no user verdict
- README doesn't reflect the V2 architecture (preflight, lookup, activate scripts)
- Test Scenario 1 (the test doc) was written for the OLD skill — needs re-validation with the new one

**Risk if we skip validation:** Publish a broken plugin and build on bad foundations.

---

## Phase 1: Automated Test Baseline (5 min)

Confirm nothing regressed since Sprint 1.

### Step 1.1: Run full test suite

```bash
cd "/Users/Aakash/Claude Projects/Flight Mode"
bash tests/run-tests.sh 2>&1 | tail -5
```

**Pass:** All 173 tests pass (or current count — confirm exact number).
**Fail:** Any test failure → investigate and fix before continuing.

### Step 1.2: Run V2-specific test files individually

```bash
for t in tests/test-v2-*.sh; do echo "=== $(basename $t) ==="; bash "$t" 2>&1 | tail -3; echo; done
```

**Pass:** All V2 tests pass. Note exact counts per file.
**Fail:** Identify which subsystem is broken.

### Step 1.3: Validate all JSON data files

```bash
for f in data/*.json; do jq . "$f" > /dev/null 2>&1 && echo "OK: $f" || echo "FAIL: $f"; done
```

**Pass:** All JSON files valid.

---

## Phase 2: Script-by-Script Smoke Tests (15 min)

Test each new script in isolation before testing the full chain.

### Step 2.1: parse-flight.sh

```bash
# Full input
echo '{"input": "CX HKG-LAX", "plugin_dir": "/Users/Aakash/Claude Projects/Flight Mode"}' | bash scripts/parse-flight.sh

# Flight code only
echo '{"input": "CX624", "plugin_dir": "/Users/Aakash/Claude Projects/Flight Mode"}' | bash scripts/parse-flight.sh

# No input
echo '{"input": "", "plugin_dir": "/Users/Aakash/Claude Projects/Flight Mode"}' | bash scripts/parse-flight.sh
```

**Pass criteria:**
- Full input: airline_code=CX, origin=HKG, destination=LAX, confidence=high, needs_route=false
- Flight code: airline_code=CX, needs_route=true
- No input: confidence=none

### Step 2.2: network-detect.sh

```bash
echo '{"plugin_dir": "/Users/Aakash/Claude Projects/Flight Mode"}' | bash scripts/network-detect.sh
```

**Pass:** Returns JSON with ssid, type, provider, confidence. No crash.

### Step 2.3: flight-check.sh

```bash
echo '{"plugin_dir": "/Users/Aakash/Claude Projects/Flight Mode"}' | bash scripts/flight-check.sh
```

**Pass:** Returns JSON with verdict (GO/CAUTION/BLOCKED/OFFLINE), api_reachable, latency, egress info. No crash. Reasonable values.

### Step 2.4: flight-on-lookup.sh

```bash
# Known airline, long-haul
echo '{"airline_code":"CX","origin":"HKG","destination":"LAX","plugin_dir":"/Users/Aakash/Claude Projects/Flight Mode","dashboard_dir":""}' | bash scripts/flight-on-lookup.sh

# Known airline, domestic
echo '{"airline_code":"DL","origin":"JFK","destination":"LAX","plugin_dir":"/Users/Aakash/Claude Projects/Flight Mode","dashboard_dir":""}' | bash scripts/flight-on-lookup.sh

# Unknown airline
echo '{"airline_code":"XX","origin":"JFK","destination":"LAX","plugin_dir":"/Users/Aakash/Claude Projects/Flight Mode","dashboard_dir":""}' | bash scripts/flight-on-lookup.sh
```

**Pass criteria:**
- CX HKG-LAX: rating=USABLE, corridor matched (transpacific), duration ~13h, waypoints array
- DL JFK-LAX: rating=GOOD (domestic), corridor matched (us-domestic), duration ~5h
- XX JFK-LAX: rating=USABLE (default), corridor still matches

### Step 2.5: flight-on-activate.sh

```bash
mkdir -p /tmp/flight-validate-test
echo '{"airline_code":"CX","airline_name":"Cathay Pacific","origin":"HKG","destination":"LAX","provider":"gogo","rating":"USABLE","stable_window":"20-40","duration_hours":13,"api_verdict":"GO","egress_country":"US","dashboard_url":"http://localhost:8234","weak_zone":{"start_hour":5,"end_hour":8,"reason":"Central Pacific"},"calibration":{"batch_size":"1-2","checkpoint_interval":"2-3","commit_interval":"2-3"},"cwd":"/tmp/flight-validate-test"}' | bash scripts/flight-on-activate.sh
```

Then verify:
```bash
cat /tmp/flight-validate-test/FLIGHT_MODE.md
echo "---"
cat /tmp/flight-validate-test/.flight-state.md
rm -rf /tmp/flight-validate-test
```

**Pass criteria:**
- FLIGHT_MODE.md: airline, route, rating, 7 condensed protocol rules, weak zone line
- .flight-state.md: session header, "awaiting user input" state, recovery instructions

### Step 2.6: flight-on-preflight.sh (full chain)

```bash
# Full args — should run all scripts and return ready=true
bash scripts/flight-on-preflight.sh "CX HKG-LAX" "/Users/Aakash/Claude Projects/Flight Mode"

# Partial args — should return ready=false, missing=["route"]
bash scripts/flight-on-preflight.sh "CX624" "/Users/Aakash/Claude Projects/Flight Mode"

# No args — should return ready=false, missing=["airline","route"]
bash scripts/flight-on-preflight.sh "" "/Users/Aakash/Claude Projects/Flight Mode"
```

**Pass criteria:**
- Full args: all 5 sections populated, ready=true, missing=[], lookup has rating+corridor
- Partial: ready=false, missing=["route"], lookup=null
- No args: ready=false, missing=["airline","route"], lookup=null
- Dashboard started (check `curl -s -o /dev/null -w '%{http_code}' http://localhost:8234/`)

**Cleanup after preflight tests:**
```bash
echo '{"command":"stop","plugin_dir":"/Users/Aakash/Claude Projects/Flight Mode"}' | bash scripts/dashboard-server.sh
```

### Step 2.7: block-direct-flight-mode.sh (PreToolUse hook)

```bash
# Should DENY
echo '{"tool_name":"Write","tool_input":{"file_path":"/some/repo/FLIGHT_MODE.md","content":"test"}}' | bash scripts/block-direct-flight-mode.sh

# Should ALLOW (no output)
echo '{"tool_name":"Write","tool_input":{"file_path":"/some/repo/README.md","content":"test"}}' | bash scripts/block-direct-flight-mode.sh
```

**Pass:** First returns permissionDecision=deny. Second returns empty (exit 0).

### Step 2.8: dashboard-server.sh

```bash
echo '{"command":"start","plugin_dir":"/Users/Aakash/Claude Projects/Flight Mode"}' | bash scripts/dashboard-server.sh
```

Then verify:
```bash
curl -s -o /dev/null -w '%{http_code}' http://localhost:8234/
ls /tmp/flight-mode-dashboard-*/index.html
```

**Pass:** HTTP 200, index.html exists.

**Cleanup:**
```bash
echo '{"command":"stop","plugin_dir":"/Users/Aakash/Claude Projects/Flight Mode"}' | bash scripts/dashboard-server.sh
```

---

## Phase 3: Live Skill Smoke Test (15 min)

The critical test. Does the deterministic redesign actually work as a skill?

### Step 3.1: Verify plugin loads

```bash
# Load plugin from local dir (don't use installed cache — test source of truth)
claude --plugin-dir "/Users/Aakash/Claude Projects/Flight Mode" --print-plugins 2>&1 || echo "Try: claude --plugin-dir . and check /hooks"
```

If `--print-plugins` doesn't exist, start a session and run `/hooks` to verify hooks are loaded.

### Step 3.2: Test /flight-on with full args (ground WiFi)

In a test repo:
```bash
mkdir -p /tmp/flight-test-repo && cd /tmp/flight-test-repo && git init && git commit --allow-empty -m "init"
```

Then start Claude with the plugin:
```bash
claude --plugin-dir "/Users/Aakash/Claude Projects/Flight Mode"
```

Run: `/flight-on CX HKG-LAX`

**Pass criteria (from Test Scenario 1, adapted for new architecture):**
1. Preflight JSON appears in Claude's context (injected by `!`command``)
2. Claude reads the `ready` field (should be true)
3. Claude presents summary with correct data (USABLE, gogo, HKG-LAX, ~13h)
4. Claude asks "Activate flight mode? (y/n)" — **HARD GATE**
5. Dashboard is running at localhost:8234
6. User says "n" → Claude acknowledges, no FLIGHT_MODE.md created

**Fail indicators:**
- Claude ignores preflight output and asks for flight info anyway
- Claude skips the confirmation gate
- Claude writes FLIGHT_MODE.md directly (hook should block this)
- Preflight script errors out (shows `{"error":"preflight failed"}`)
- No dashboard started

### Step 3.3: Test /flight-on with no args

Same setup. Run: `/flight-on`

**Pass criteria:**
1. Preflight runs but with ready=false, missing=["airline","route"]
2. Claude asks "What flight are you on?"
3. User provides "DL JFK-LAX"
4. Claude runs lookup script
5. Claude presents summary with GOOD rating
6. Claude asks to activate

### Step 3.4: Test /flight-on → activate → /flight-off

Run: `/flight-on CX HKG-LAX`, say "y" to activate.

**Pass criteria:**
1. FLIGHT_MODE.md created (via activate script, not direct Write)
2. .flight-state.md created
3. Claude asks what to work on
4. Say "add a comment to README.md"
5. Claude decomposes into micro-tasks
6. Let Claude do 1-2 tasks
7. Run `/flight-off`
8. Summary shown, squash offered, cleanup done

**Cleanup:**
```bash
rm -rf /tmp/flight-test-repo
```

### Step 3.5: Test PreToolUse hook live

During an active `/flight-on` session, ask Claude to "write FLIGHT_MODE.md with custom content."

**Pass:** Hook blocks the Write tool. Claude gets denial message and uses the activate script instead.

---

## Phase 4: Issue Triage & Fixes

Based on Phase 1-3 results, categorize findings:

### Critical (blocks shipping)
- Preflight script fails or returns malformed JSON
- Claude ignores preflight output (LLM drift not fixed)
- Activate script produces malformed FLIGHT_MODE.md
- /flight-off corrupts git history

### Major (fix before shipping)
- Dashboard doesn't start or render correctly
- Lookup returns wrong rating/corridor
- Context monitor thresholds miscalibrated
- Hook doesn't block

### Minor (can ship, fix later)
- Cosmetic issues in summary formatting
- Edge case in unknown airline handling
- Dashboard tooltip rendering

**For each issue found:**
1. Create a Notion roadmap item (Status=Backlog, Source=Verification Failure, Sprint#=2)
2. Fix critical issues immediately on a branch
3. Queue major issues for next work session
4. Note minor issues for later

---

## Phase 5: Close Sprint 1 Items (10 min)

Based on Phase 1-3 results, update Notion roadmap:

### Verifying → Shipped (if tests pass)
- Plugin scaffold
- /flight-on skill
- /flight-off skill
- Flight profiles
- FLIGHT_MODE.md template + snippet
- stop-checkpoint.sh
- context-monitor.sh
- Automated test suite
- V2 Feature Build

### Verifying → Backlog (if tests fail)
Move back with Source=Verification Failure and notes on what failed.

### In Progress items
- **Latency measurement script**: The script works. CSV data was collected on the CX flight. Mark Shipped or close out.
- **In-flight user testing**: Was partially done (old architecture). Mark as Backlog — needs re-run with new deterministic skill. Create new item for Sprint 2 if needed.

### Planned items to re-assess
- **README.md**: Already exists but needs update for V2 architecture. Re-scope.
- **End-to-end testing**: Being done NOW in Phase 3. Update status.
- **Publish to GitHub**: After validation passes. Keep Planned.
- **Plugin hooks.json**: Already done (hooks.json exists with all 3 hook types). Should be Shipped.

---

## Phase 6: README & Publish (15 min)

Only after Phase 1-5 pass.

### Step 6.1: Update README.md

Current README is stale — mentions the old structure, doesn't mention:
- `scripts/flight-on-preflight.sh` (orchestrator)
- `scripts/flight-on-lookup.sh` (profile + corridor matching)
- `scripts/flight-on-activate.sh` (FLIGHT_MODE.md creation)
- `scripts/block-direct-flight-mode.sh` (safety hook)
- `scripts/parse-flight.sh`, `network-detect.sh`, `flight-check.sh`
- `data/airline-profiles.json`, `airport-codes.json`, `route-corridors.json`, etc.
- `templates/dashboard.html`
- `/flight-check` skill
- Dashboard at localhost:8234
- V2 test files (test-v2-*.sh)

Update the Plugin Structure section and add V2 features section.

### Step 6.2: Push to GitHub

```bash
git push origin main
```

### Step 6.3: Tag release

```bash
git tag -a v2.0.0 -m "V2: deterministic activation, flight parsing, network detection, API geo-check, dashboard, route corridors"
git push origin v2.0.0
```

### Step 6.4: Update plugin cache

```bash
cp -r "/Users/Aakash/Claude Projects/Flight Mode/"* ~/.claude/plugins/cache/flight-mode-plugins/flight-mode/2.0.0/
```

(Exact cache path may vary — check `~/.claude/plugins/installed_plugins.json`.)

---

## Phase Summary

| Phase | Duration | Blocks Next? |
|-------|----------|-------------|
| 1: Automated tests | 5 min | Yes — if tests fail, stop |
| 2: Script smoke tests | 15 min | Yes — if scripts broken, can't test skill |
| 3: Live skill smoke test | 15 min | Yes — if skill broken, can't ship |
| 4: Issue triage & fixes | Variable | Yes — critical issues block shipping |
| 5: Close Sprint 1 items | 10 min | No |
| 6: README & publish | 15 min | No |

**Total estimated: ~60 min** if everything passes. More if issues found.

**Exit criteria for Sprint 2:**
- All automated tests pass
- `/flight-on` with full args works end-to-end (preflight → summary → gate → activate)
- `/flight-on` with no args works (asks, then lookup → summary → gate → activate)
- `/flight-off` works (summary → squash → cleanup)
- PreToolUse hook blocks direct FLIGHT_MODE.md writes
- All Verifying items resolved (Shipped or back to Backlog)
- README reflects current architecture
- Pushed to GitHub with v2.0.0 tag

---

## Sprint 3 Candidates (not for now — just noting)

After Sprint 2 validation passes, potential Sprint 3 items:
- Re-run in-flight user testing with deterministic skill (next flight)
- Auto-detection via latency measurement (V2 future enhancement)
- Dashboard visual polish + live latency chart integration
- SessionStart hook for auto-detecting FLIGHT_MODE.md (remove CLAUDE.md snippet need)
- Marketplace submission (when Claude Code marketplace is ready)
- context-monitor.sh calibration (real-world data from CX flight measurements)
