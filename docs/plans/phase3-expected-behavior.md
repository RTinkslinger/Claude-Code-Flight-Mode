# Phase 3: Live Skill Test — Expected Behavior

**Date:** 2026-03-10
**Environment:** Ground WiFi, /tmp/flight-test-repo, plugin loaded via `--plugin-dir`

---

## Setup (Steps 1-2)

```bash
# Step 1
mkdir -p /tmp/flight-test-repo && cd /tmp/flight-test-repo && git init && git commit --allow-empty -m "init"

# Step 2
claude --plugin-dir "/Users/Aakash/Claude Projects/Flight Mode"
```

**Expected:** Claude starts. Plugin loads. `/flight-on`, `/flight-off`, `/flight-check` available as slash commands.

**Pre-test:** Confirm no dashboard is running yet:
- http://localhost:8234 → should NOT respond (connection refused)

---

## Test A: `/flight-on CX HKG-LAX` + Decline (Steps 3-4)

### What happens under the hood

1. SKILL.md loads → `!`command`` injection executes `flight-on-preflight.sh "CX HKG-LAX" "<plugin-dir>"`
2. Preflight orchestrator runs 5 scripts sequentially:
   - `parse-flight.sh` → airline_code=CX, origin=HKG, destination=LAX, confidence=high, needs_route=false
   - `network-detect.sh` → ssid=null (or current WiFi), type=none/other
   - `flight-check.sh` → verdict=GO, api_reachable=true, ~30-50ms latency, egress US
   - `dashboard-server.sh start` → starts HTTP server on port 8234, creates `/tmp/flight-mode-dashboard-<hash>/`
   - `flight-on-lookup.sh` → rating=USABLE, corridor=transpacific-north, duration=13h, 16 waypoints, weak_zone hours 5-8
3. Preflight returns single JSON blob with `ready: true, missing: []`
4. This JSON is injected as static text at the top of the skill prompt under "## Preflight Results"

### Expected Claude behavior (what you should SEE)

**3a. Preflight JSON visible in context**
Claude receives the preflight JSON. It may or may not display the raw JSON to you — that's fine. What matters is Claude's interpretation of it.

**3b. Claude skips to Step 3 (Summary)**
Since `ready: true`, Claude should NOT ask you any questions about flight details. It goes straight to presenting the summary.

**3c. Summary presented**
Claude should show something close to:

```
Flight Mode: Cathay Pacific CX
Route: HKG → LAX (~13h)
WiFi: gogo · Rating: USABLE
API Status: GO via US
Network: [ssid or "no WiFi detected"] ([type])
Dashboard: http://localhost:8234

Calibration:
- Micro-task batch: 1-2 at a time
- Checkpoint every: 2-3 tasks
- Git commit every: 2-3 tasks

Connectivity Timeline:
  Hours 0-5: Strong signal
  Hours 5-8: WEAK ZONE — Sparse GEO beams over central North Pacific
  Hours 8-13: Signal recovery

Activate flight mode? (y/n)
```

**Key fields to verify:**
- Airline: Cathay Pacific CX (not null, not "Unknown")
- Route: HKG → LAX (not reversed, not missing)
- Rating: USABLE (not GOOD, not UNKNOWN)
- Duration: ~13h (not 5h, not null)
- Provider: gogo
- Verdict: GO (not BLOCKED, not OFFLINE)
- Weak zone: hours 5-8 mentioned
- Dashboard URL: http://localhost:8234
- Calibration: 1-2 batch, 2-3 checkpoint/commit (matches USABLE)

**3d. HARD GATE — Confirmation asked**
Claude MUST ask "Activate flight mode? (y/n)" or equivalent before proceeding. This is the hard gate. If Claude activates without asking → CRITICAL FAIL.

**3e. Dashboard is running — OPEN IN BROWSER**
At this point (before you answer y/n), the dashboard should already be running.

**Action: Open http://localhost:8234 in your browser.**

Verify the dashboard renders:
- [ ] Page loads (not blank, not "connection refused")
- [ ] Flight code area shows "CX" or "CX HKG-LAX"
- [ ] Route "HKG → LAX" visible
- [ ] Airline "Cathay Pacific" visible
- [ ] Provider "gogo" visible
- [ ] Rating badge shows "USABLE"
- [ ] Connectivity Timeline SVG chart renders with waypoint line
- [ ] Weak zone (hours 5-8) marked on chart — line dips into orange/red zone
- [ ] Duration shows ~13h on x-axis
- [ ] Status cards section visible (may show "—" for live data)
- [ ] Live Latency chart shows "Waiting for data..."
- [ ] Drop Log table visible (shows "No drops detected")
- [ ] Auto-refresh dot visible (green pulsing)

**Note:** route-data.json is written during preflight. If the chart shows no data or "No route data", the write-route step may not have fired — check log capture.

**Leave the browser tab open** — you'll check it again in Test C.

### Step 4: User says "n"

**Expected Claude behavior:**
- Claude acknowledges: "Flight mode not activated" or similar
- Claude may mention: "Dashboard is live at http://localhost:8234"
- Claude does NOT run the activate script
- Claude does NOT write FLIGHT_MODE.md
- Claude does NOT create .flight-state.md

**Filesystem verification (log capture will check):**
- `/tmp/flight-test-repo/FLIGHT_MODE.md` → MUST NOT EXIST
- `/tmp/flight-test-repo/.flight-state.md` → MUST NOT EXIST
- Dashboard dir still exists (dashboard was started during preflight, not stopped on decline)

**PASS criteria:**
- [ ] Summary shown with correct data
- [ ] Confirmation gate asked
- [ ] "n" respected — no activation
- [ ] No FLIGHT_MODE.md in test repo
- [ ] No .flight-state.md in test repo
- [ ] Dashboard loaded in browser (HTTP 200)
- [ ] Dashboard shows CX route with connectivity chart
- [ ] Weak zone visible on chart (hours 5-8 dip)

**FAIL indicators:**
- Claude asks for flight info despite full args provided → preflight injection failed
- Claude activates without asking → hard gate not enforced
- FLIGHT_MODE.md exists after saying "n" → activation script ran anyway
- Summary shows nulls, dashes, or "Unknown" for CX data → lookup failed
- No mention of weak zone → lookup data not consumed
- Dashboard not running → dashboard-server.sh failed

---

## Test B: `/flight-on` with no args (Step 5)

### What happens under the hood

1. SKILL.md loads → `!`command`` injection executes `flight-on-preflight.sh "" "<plugin-dir>"`
2. Preflight orchestrator:
   - `parse-flight.sh` → all nulls, confidence=none, needs_route=false
   - `network-detect.sh` → same as before
   - `flight-check.sh` → same as before (GO)
   - `dashboard-server.sh start` → returns `already_running` (still up from Test A)
   - Lookup is SKIPPED (ready=false)
3. Preflight returns JSON with `ready: false, missing: ["airline", "route"]`, `lookup: null`

### Expected Claude behavior

**5a. Claude reads `ready: false` → goes to Step 2 (Fill missing info)**

**5b. Claude asks ONE question**
Since `missing: ["airline", "route"]`, Claude should ask something like:
> "What flight are you on? (e.g., CX624 BLR-HKG)"

Claude should NOT ask two separate questions (one for airline, one for route). The skill says "Ask the user ONE question to fill the gaps."

**5c. After user responds (e.g., "DL JFK-LAX")**
Claude should run the lookup script:
```bash
echo '{"airline_code":"DL","origin":"JFK","destination":"LAX","plugin_dir":"...","dashboard_dir":"..."}' | bash scripts/flight-on-lookup.sh
```

**5d. Claude presents summary**
Same format as Test A but with Delta data:
- Airline: Delta DL
- Route: JFK → LAX (~5h)
- WiFi: gogo · Rating: GOOD
- No weak zone (US domestic)
- Calibration: up to 3 batch, 3-4 checkpoint/commit (GOOD rating)

**5e. Hard gate — asks to activate**
> "Activate flight mode? (y/n)"

For this test, say "n" to move on to Test C.

**5f. Dashboard check (optional)**
The dashboard is still running from Test A. If you refresh http://localhost:8234, route-data.json may still show CX data (dashboard-server was `already_running`, so the route-data wasn't rewritten for DL). This is expected — the dashboard only gets fresh route-data on a fresh `start`, not `already_running`. Not a bug for now; server lifecycle improvements are tracked in backlog.

**PASS criteria:**
- [ ] Claude does NOT ask for flight info that was already provided (none here — all missing is correct)
- [ ] Claude asks ONE question for both airline and route
- [ ] After answer, Claude runs lookup and presents summary
- [ ] Summary shows GOOD rating (not USABLE) for Delta domestic
- [ ] No weak zone shown (correct for us-domestic corridor)
- [ ] Confirmation gate asked

**FAIL indicators:**
- Claude presents a summary with nulls/unknowns without asking for input → didn't read missing array
- Claude asks separate questions for airline and route → didn't follow "ONE question" rule
- Claude skips lookup and tries to activate with no data → dangerous
- Summary shows USABLE instead of GOOD for Delta → lookup returned wrong data

---

## Test C: `/flight-on CX HKG-LAX` + Accept + `/flight-off` (Steps 6-7)

### Step 6: Accept activation

Same as Test A flow (preflight runs again, summary shown). User says "y".

### What happens after "y"

1. Claude runs `flight-on-activate.sh` with all collected data via stdin JSON
2. Activate script creates:
   - `FLIGHT_MODE.md` in `/tmp/flight-test-repo/`
   - `.flight-state.md` in `/tmp/flight-test-repo/`
3. Activate script returns: `{"status": "activated", "flight_mode_path": "...", "flight_state_path": "..."}`

### Expected Claude behavior after activation

**6a. Claude confirms activation succeeded**
Something like: "Flight mode activated" + brief confirmation.

**6b. Claude checks .gitignore (Step 5 of SKILL.md)**
Claude should check if `.gitignore` exists and whether `FLIGHT_MODE.md` and `.flight-state.md` are listed. Since this is a fresh test repo with no `.gitignore`, Claude should suggest:

> Note: FLIGHT_MODE.md and .flight-state.md are runtime files.
> I recommend adding them to .gitignore:
>
>   FLIGHT_MODE.md
>   .flight-state.md
>   .flight-state-*.md
>
> Want me to add these? (y/n)

Say "y" (or "n" — either is fine for testing, but "y" tests the gitignore write).

**6c. Claude asks for task**
> "What do you want to work on this flight?"

**6d. User gives a simple task**
Say something like: "add a comment to README.md"

Claude should:
- Decompose into micro-tasks (even if trivial: "1. Create README.md with comment")
- Update `.flight-state.md` with the micro-task plan
- Execute the first micro-task
- After completing: one-line status update
- After checkpoint interval (2-3 tasks): git commit with `flight:` prefix

**Filesystem verification:**
- `/tmp/flight-test-repo/FLIGHT_MODE.md` → EXISTS, contains correct data
- `/tmp/flight-test-repo/.flight-state.md` → EXISTS, shows task plan
- Dashboard running at http://localhost:8234

**6e. Dashboard check — REFRESH BROWSER**
Refresh http://localhost:8234. The dashboard was restarted during this preflight (new `start` since previous was stopped or same session). Check:
- [ ] Route still shows CX HKG-LAX data
- [ ] Connectivity timeline chart still renders
- [ ] If you activated with a task, live-data.json may start getting updates from context-monitor

**6f. PreToolUse hook active**
During the session, the `block-direct-flight-mode.sh` hook is running on every Write tool call. If Claude tries to Write to FLIGHT_MODE.md directly (it shouldn't — the activate script already created it), the hook will deny it. This is passive — you won't see it unless Claude tries something wrong.

### Step 7: `/flight-off`

### What happens under the hood

1. SKILL.md for flight-off loads (no `!`command`` injection — it's a prompt-only skill)
2. Claude follows the 8-step deactivation protocol

### Expected Claude behavior

**7a. Claude reads FLIGHT_MODE.md and .flight-state.md**
Gets airline, route, rating, activation time, task completion status.

**7b. Claude counts flight commits**
Runs: `git log --oneline --all | grep "flight:" | wc -l`
Result depends on how many commits were made during step 6.

**7c. Summary shown**
```
Flight Mode Summary
━━━━━━━━━━━━━━━━━━
Airline: Cathay Pacific CX HKG-LAX
WiFi Rating: USABLE
Session: [activation time] → now

Tasks: [completed]/[total] completed
Files modified: [list]
Flight commits: [N]
```

If there are incomplete tasks, they're listed.

**7d. Commit squash offered (if 2+ flight commits)**
If Claude made 2+ `flight:` commits:
> "You have N flight: commits. Squash them into a single commit? (y/n)"

Say "y" or "n" — either tests the flow. "y" tests the non-interactive squash.

If 0-1 commits, this step is skipped.

**7e. Incomplete tasks noted**
If any micro-tasks are incomplete, Claude lists them and says they can be finished in a normal session.

**7f. State archived**
Claude runs: `mv .flight-state.md ".flight-state-2026-03-10.md"`

**7g. FLIGHT_MODE.md removed**
Claude runs: `rm FLIGHT_MODE.md`

**7h. Confirmation**
> "Flight mode off. Back to normal operations."

**Filesystem verification:**
- `/tmp/flight-test-repo/FLIGHT_MODE.md` → MUST NOT EXIST (removed)
- `/tmp/flight-test-repo/.flight-state.md` → MUST NOT EXIST (archived)
- `/tmp/flight-test-repo/.flight-state-2026-03-10.md` → EXISTS (archive)
- Git log shows either squashed commit or individual `flight:` commits

**7i. Dashboard after /flight-off**
The dashboard server is still running (flight-off doesn't stop it). http://localhost:8234 should still respond. The data is now stale (FLIGHT_MODE.md gone, no more context-monitor updates), but the server process persists until manually stopped or the temp dir is cleaned.

This is a known gap — dashboard server lifecycle (auto-stop on /flight-off, cleanup of temp dirs) is tracked as a backlog item.

**PASS criteria:**
- [ ] Summary shown with correct airline, route, rating
- [ ] Task completion count accurate
- [ ] Squash offered if 2+ commits (and works if accepted)
- [ ] .flight-state.md renamed to dated version
- [ ] FLIGHT_MODE.md removed
- [ ] "Flight mode off" confirmation shown
- [ ] Dashboard still accessible (server not crashed)

**FAIL indicators:**
- Claude says "flight mode not active" despite FLIGHT_MODE.md existing → read failed
- Squash corrupts git history → git reset --soft went wrong
- FLIGHT_MODE.md still exists after /flight-off → cleanup failed
- .flight-state.md not archived → rename failed

---

## Dashboard Server Lifecycle (Known Gap)

The dashboard server starts during preflight and is never automatically stopped. Current behavior:
- `/flight-on` (preflight) → starts server
- `/flight-on` again → returns `already_running`
- `/flight-off` → does NOT stop server
- Session end → does NOT stop server
- Server persists until: manual stop, reboot, or `/tmp` cleanup

**This is acceptable for v2.0.0 shipping.** Server lifecycle improvements (auto-stop on /flight-off, session-end cleanup, stale dashboard detection) are tracked in the Notion roadmap backlog.

---

## Hook Behavior Throughout All Tests

### PreToolUse (block-direct-flight-mode.sh)
- Fires on EVERY Write tool call
- Only produces output (deny) if target file is FLIGHT_MODE.md
- Silent (no output) for all other files → no overhead

### PostToolUse (context-monitor.sh)
- Fires after every Read, Edit, Write, Bash, Grep, Glob
- Only produces output if FLIGHT_MODE.md exists AND thresholds are hit
- Before Test C activation: FLIGHT_MODE.md doesn't exist → always silent
- After Test C activation: tracks tool calls, may inject warnings at 45%/65%/85%
- In a short test session, unlikely to hit thresholds → should stay silent

### Stop (stop-checkpoint.sh)
- Fires when session ends
- Only acts if FLIGHT_MODE.md exists AND there are uncommitted tracked changes
- Will auto-commit with "flight: auto-checkpoint on session end"
- If you `/flight-off` first (which removes FLIGHT_MODE.md), stop hook becomes a no-op

---

## Quick Reference: What to Watch For

| Moment | Critical Check |
|--------|---------------|
| After `/flight-on CX HKG-LAX` | Summary has correct CX data, not nulls |
| Before you answer y/n | Dashboard at localhost:8234 responds |
| After saying "n" | No FLIGHT_MODE.md created |
| After `/flight-on` (no args) | Claude asks ONE question for flight info |
| After providing "DL JFK-LAX" | Summary shows GOOD (not USABLE) |
| After saying "y" to activate | FLIGHT_MODE.md + .flight-state.md exist |
| Claude asks for task | .gitignore check happens first |
| During work | `flight:` prefix on commits |
| After `/flight-off` | FLIGHT_MODE.md gone, state archived |
