# Iteration 1 — Product Audit & Gap Analysis

**Date:** 2026-03-18
**Plugin Version:** 2.0.0
**Test Suite:** 173 tests passing
**Auditor:** Product Lead (Claude Opus 4.6)

---

## 1. Feature Completeness Review

### 1.1 User-Facing Flows

| Flow | Status | Notes |
|------|--------|-------|
| `/flight-on` activation | Functional | Full preflight orchestrator, deterministic checks |
| `/flight-on` with flight code (e.g., `CX884`) | Functional | Parsed correctly, needs_route=true triggers follow-up |
| `/flight-on` with airline+route (e.g., `CX HKG-LAX`) | Functional | Full end-to-end including corridor lookup |
| `/flight-on` with no args | Functional | Prompts user for info |
| `/flight-off` deactivation | Functional with caveats | See 1.2 |
| `/flight-check` connectivity | Functional | DNS, HTTPS, geo-IP, latency, download speed |
| Dashboard at localhost:8234 | Functional with bugs | See Section 4 |
| Session recovery via FLIGHT_MODE.md | Functional | Requires CLAUDE.md snippet |
| Stop hook auto-checkpoint | Functional | Tested, uses --no-verify |
| Context budget warnings | Functional | Thresholds at 45%, 65%, 85% |
| PreToolUse write guard | Functional | Blocks direct FLIGHT_MODE.md writes |

### 1.2 Critical Gaps: Promised but Not Implemented

**P0 — Dashboard not stopped on `/flight-off`**
`skills/flight-off/SKILL.md` (all 119 lines) never mentions stopping the dashboard server. When the user deactivates flight mode, the Python HTTP server continues running on port 8234 indefinitely. The dashboard-server.sh has a `stop` command, but `/flight-off` never invokes it.
- File: `skills/flight-off/SKILL.md`
- Missing: A Step 6.5 that runs `echo '{"command":"stop"}' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/dashboard-server.sh"`

**P0 — Squash logic is dangerously wrong**
The squash command in `skills/flight-off/SKILL.md` line 70-73:
```bash
BEFORE_FLIGHT=$(git log --oneline | grep -v "flight:" | head -1 | cut -d' ' -f1)
git reset --soft $BEFORE_FLIGHT
```
This finds the first non-`flight:` commit in `git log --oneline` output. But `git log --oneline` lists commits newest-first. If the user has interleaved non-flight commits (or if the initial commit is very old), this `grep -v | head -1` will grab the most recent non-flight commit, NOT the commit just before the first flight commit. This would squash only the flight commits above it, potentially missing earlier flight commits or incorrectly including non-flight commits in the reset.

Correct approach: walk the log from top until you find the first non-flight commit, which IS what `grep -v | head -1` does from the top. BUT if ALL visible commits are flight commits, `head -1` returns nothing and `git reset --soft` gets an empty argument, which is undefined behavior. Also, the same flawed logic appears in `skills/flight-on/SKILL.md` lines 190-193 (Post-Flight Squash Reference section).

**P1 — Airline codes data gap: F9 (Frontier) and NK (Spirit) missing**
`data/airline-profiles.json` has profiles for `F9` (Frontier) and `NK` (Spirit), but `data/airline-codes.json` does not contain either code. The parser (`scripts/parse-flight.sh`) looks up airline codes from `airline-codes.json`. A user typing `/flight-on F9 DEN-LAX` would get a "low confidence" match at best (Strategy 1 fallback: generic 2-letter code) with no airline name, no provider, and no connection to the Frontier profile. The POOR rating for Frontier would never be applied.

**P1 — No `F9`/`NK` entries in airline-codes.json**
- `F9` should map to `{"name": "Frontier Airlines", "provider": "none", "country": "US"}`
- `NK` should map to `{"name": "Spirit Airlines", "provider": "ses", "country": "US"}`

### 1.3 Missing Error States and User Feedback

**P1 — No user feedback when preflight fails**
In `skills/flight-on/SKILL.md` line 13, the `!` command has a fallback:
```bash
|| echo '{"error":"preflight failed","ready":false,"missing":["airline","route"]}'
```
But the SKILL.md instructions (Step 1) only check `ready` and `missing` fields. There is no handling for the `error` field. If preflight fails due to missing `jq`, missing `python3`, or a script crash, the user gets asked for airline+route (because `missing=["airline","route"]`) rather than being told "preflight failed." The error goes silent.

**P1 — No validation of user's lookup response**
In Step 2 of `/flight-on` SKILL.md, after the user provides the airline/route, Claude runs `flight-on-lookup.sh`. But there is no instruction for what to do if the lookup returns an error or null values. If the airline code is unrecognized, the user gets a degraded summary with "Unknown" everywhere but no explicit "I couldn't find this airline" message.

**P2 — Context monitor formula is opaque**
`scripts/context-monitor.sh` line 66-69 uses the formula `(tool_calls * 2.5 + lines_read * 0.01) / 1.5`. The comment says "1.5 is a normalization factor that maps to ~100% at typical session limits." But this is untestable -- the "typical session limit" is undefined. At 60 tool calls with 3000 lines read, this gives `(150 + 30) / 1.5 = 120%`. Is that realistic? The formula has no empirical grounding documented anywhere.

**P2 — No latency CSV logging integration**
`scripts/measure-latency.sh` exists for manual CSV-based latency logging, but nothing in the plugin invokes it or references it. The README mentions it in the file tree but never explains when or how to use it. It is an orphaned utility.

---

## 2. UX Flow Analysis

### 2.1 New User: Installation and First Activation

**Step 1: Clone the repo**
Clear instructions. Two options (local plugin, marketplace placeholder). The alias suggestion is helpful.

**Friction point (P2):** The README says "Option B: Marketplace (when available)" with `claude plugin install flight-mode`. This is misleading because it suggests the marketplace path works. It should say "Coming soon" or be removed.

**Step 2: One-time CLAUDE.md setup**
The README says this is "optional but enables seamless session recovery." This undersells it. Without the snippet, session recovery requires the user to manually type "read FLIGHT_MODE.md" -- not obvious to a new user in a panic after a WiFi drop.

**Friction point (P1):** There is no `/flight-setup` or first-run command that automatically adds the CLAUDE.md snippet. The user must manually edit `~/.claude/CLAUDE.md`. This is the single biggest adoption barrier. A user who skips this step will have degraded recovery and may not understand why.

**Step 3: First `/flight-on`**
The preflight orchestrator runs automatically. This is excellent UX -- the user sees results without needing to understand the pipeline.

**Friction point (P2):** If the user runs `/flight-on` while on the ground (e.g., at an airport), the network detection will identify airport WiFi, the API check will show GO, but the dashboard will show "Waiting for data..." because there is no route-data yet. The timeline chart will be empty. This is confusing -- the user may think the dashboard is broken.

**Step 4: Confirmation gate**
The hard gate ("Activate flight mode? y/n") is correctly mandatory. Good UX.

**Friction point (P2):** After confirmation, the SKILL.md asks the user "What do you want to work on?" This is fine, but if the user already stated their task in the `/flight-on` invocation (e.g., `/flight-on CX884 — I want to refactor the auth module`), that task is lost because `$ARGUMENTS` is fed only to the parse-flight script, which ignores non-flight text.

### 2.2 Mid-Flight Drop and Recovery

**Best-case flow (CLAUDE.md snippet installed):**
1. WiFi drops, session dies
2. Stop hook fires, auto-commits any changes with `flight: auto-checkpoint`
3. User reconnects, opens Claude Code
4. Claude reads CLAUDE.md, sees "read FLIGHT_MODE.md"
5. Claude reads FLIGHT_MODE.md, gets condensed protocol
6. Claude reads `.flight-state.md`, resumes from last incomplete task

This works well architecturally.

**Friction point (P0):** The stop hook uses `--no-verify` (line 35 of `stop-checkpoint.sh`). This is documented as intentional ("pre-commit hooks should not prevent saving work"). However, if the user has a pre-commit hook that reformats code, the auto-checkpoint commit will contain unformatted code. On recovery, the next session will see the unformatted code and may re-format it, creating a diff that confuses the squash logic.

**Friction point (P1):** The Stop hook only commits **tracked** file changes (line 26: `grep -v '^??'`). If the user created a new file during the session but never staged it, the stop hook will NOT save it. This is intentional (to avoid adding junk files), but it means new files created during the session can be lost on a drop. The `.flight-state.md` file itself may reference files that don't exist in git.

**Friction point (P1):** There is no mechanism to detect that the PREVIOUS session ended with a stop-hook auto-checkpoint. When the new session starts, Claude just picks up from `.flight-state.md`. It would be helpful to detect the auto-checkpoint commit and tell the user: "Your previous session was auto-saved. The last checkpoint was at commit [hash]."

### 2.3 Deactivation and Cleanup

**Step 1-3:** Summary is well-structured with airline, tasks, commits. Good.

**Friction point (P0):** Dashboard server is orphaned (see 1.2).

**Friction point (P1):** The squash offer uses `git log --oneline --all | grep "flight:" | wc -l` (line 23 of flight-off SKILL.md). The `--all` flag counts flight commits on ALL branches, not just the current one. If the user has flight commits on other branches (e.g., from a previous flight), the count will be inflated and the squash may try to include commits from other branches.

**Friction point (P1):** After squash, there is no verification step. The SKILL.md does not instruct Claude to run `git log` to show the squashed result, or `git diff` to verify nothing was lost. A destructive operation (`git reset --soft`) should always be followed by verification.

**Friction point (P2):** The archived state file (`.flight-state-YYYY-MM-DD.md`) is never mentioned in `.gitignore` by the activation flow. The activation flow (Step 5 of flight-on SKILL.md) checks for `FLIGHT_MODE.md` and `.flight-state.md` in `.gitignore`, and also mentions `.flight-state-*.md`, so this is partially covered. But if the user said "no" to the .gitignore prompt, archived state files will show up in `git status` forever.

### 2.4 Edge Case: Running `/flight-on` When Already Active

There is NO handling for this case in `skills/flight-on/SKILL.md`. If a user runs `/flight-on` while flight mode is already active:
- The preflight orchestrator runs again
- A new dashboard server may try to start (dashboard-server.sh returns `already_running`, which is fine)
- `flight-on-activate.sh` will OVERWRITE the existing `FLIGHT_MODE.md` and `.flight-state.md`
- Any in-progress task state is DESTROYED

**P1 severity.** The SKILL.md should check for existing FLIGHT_MODE.md at the start and either refuse or ask to reconfigure.

### 2.5 Edge Case: Non-Git Repository

The stop hook (`stop-checkpoint.sh` line 13) exits gracefully if `cd` fails or git is not available. The context monitor checks for FLIGHT_MODE.md but does not check for git. However, the flight-on activation script creates files in the CWD regardless of whether it is a git repo. The protocol instructs Claude to make git commits, but if there is no git repo, those commits will fail silently and the user will have no checkpoints.

**P2 severity.** The preflight should detect non-git repos and warn the user that checkpointing will be limited to `.flight-state.md` only (no git commits).

---

## 3. Gap Analysis

### 3.1 Missing From "Best in Class"

**P1 — No `/flight-setup` command**
A one-time setup command that:
- Adds the CLAUDE.md snippet automatically
- Verifies `jq` and `python3` are installed
- Runs a quick connectivity test
- Creates a `~/.flight-mode/` config directory for user preferences (preferred airlines, home airport)

This would eliminate the biggest adoption barrier (manual CLAUDE.md editing).

**P1 — No variant aircraft detection for airlines with mixed fleets**
Airlines like United (Starlink vs. legacy GEO), American (narrowbody vs. widebody), Lufthansa (legacy vs. Starlink), ANA (767 Viasat vs. 777 legacy) have dramatically different WiFi quality depending on aircraft type. The `variant_airlines` map in `airline-profiles.json` exists, but the lookup script (`flight-on-lookup.sh` lines 65-76) silently picks the **most conservative** variant. It never asks the user which aircraft they are on.

The SKILL.md should detect variant airlines and ask: "United has Starlink on some aircraft and legacy GEO on others. Do you know your aircraft type? (If not sure, I'll use conservative settings.)"

**P1 — No periodic connectivity re-check during session**
The context monitor measures latency every 3rd tool call (lines 89-181 of `context-monitor.sh`), but the measurements are only written to the dashboard JSON and state file. They are never used to adjust behavior. If connectivity degrades from GOOD to POOR mid-flight (e.g., entering a weak zone), the protocol does not re-calibrate checkpoint frequency.

A mid-session re-calibration hook could detect degrading latency and inject a warning: "Latency increasing -- entering weak zone. Increasing checkpoint frequency to every task."

**P2 — No offline mode for complete connectivity loss**
The plugin is designed for "degraded network, not offline" (system-plan-v2.md line 499). But complete connectivity loss is common (polar routes, mid-Pacific). When offline, Claude cannot make API calls at all, so the plugin cannot help. However, the state files and recovery instructions still work. A brief note in the FLIGHT_MODE.md saying "If fully offline: save files locally, I'll resume when connectivity returns" would be useful.

**P2 — No telemetry or post-flight report**
After a flight, the user has no way to see what happened. How many drops occurred? What was the average latency? How much context was consumed? The dashboard data exists in `/tmp/flight-mode-dashboard-*/live-data.json` but is ephemeral and lost on reboot. A post-flight report (generated by `/flight-off`) summarizing connectivity metrics would be valuable.

**P3 — No community contribution mechanism**
The README mentions "Contributing: submit a measurement" but there is no `measurements/` directory, no template, and no submission process.

**P3 — No integration with git stash for untracked files**
The stop hook only commits tracked files. New files are left unstaged. A `git stash --include-untracked` before the stop hook commit would save everything, but this is risky if the stash conflicts on recovery.

### 3.2 Unhandled Edge Cases

| Edge Case | Severity | Current Behavior |
|-----------|----------|-----------------|
| `/flight-on` when already active | P1 | Overwrites FLIGHT_MODE.md and .flight-state.md silently |
| Port 8234 already in use | P2 | dashboard-server.sh will fail to bind; error JSON returned but preflight continues |
| User has no WiFi (ethernet or tethered) | P2 | network-detect.sh returns `type: none`; not harmful but confusing in summary |
| Multiple Claude Code sessions with flight mode | P1 | Context monitor state files are keyed by CWD hash, so two sessions in the same repo will clobber each other's state |
| Timezone mismatch in timestamps | P2 | `date +"%Y-%m-%d %H:%M"` uses local time, but `date -u` is used for latency timestamps. Mixed timezone data in state files |
| Very long flight (>18h, e.g., SIN-JFK) | P2 | No corridor defined; duration estimated by haversine/850 = ~18.5h; dashboard timeline works but has no waypoint data |
| User runs `/flight-check` while flight mode is active | P2 | Works fine but does not reference the current flight context |

### 3.3 What Would Make a User Recommend This

Based on the current state, the plugin delivers genuine value for its core use case. What pushes it from "useful" to "must-have":

1. **Zero-friction setup** (`/flight-setup` command)
2. **Smart variant detection** ("You're on United -- Starlink or legacy?")
3. **Post-flight report** (connectivity summary, time saved)
4. **Mid-flight re-calibration** (adapt to changing conditions)
5. **Foolproof recovery** (detect auto-checkpoint, show user exactly what was saved)

---

## 4. Dashboard Assessment

### 4.1 Visual Design Quality

**Strengths:**
- Dark theme with JetBrains Mono font -- appropriate for a developer tool
- Color system is consistent and semantically meaningful (green=go, yellow=caution, red=blocked)
- SVG-based charts are clean and performant
- Stale banner ("CONNECTION LOST") is a smart UX pattern
- Tooltip on waypoint dots provides useful detail (phase, lat/lon, signal)

**Weaknesses:**

**P0 — Rating badge color mapping is broken**
File: `templates/dashboard.html` line 126:
```javascript
const m = {EXCELLENT:'badge-excellent',USABLE:'badge-usable',LIMITED:'badge-limited',POOR:'badge-poor'};
```
This maps EXCELLENT, USABLE, LIMITED, POOR. But the plugin's rating scale is EXCELLENT, **GOOD**, USABLE, **CHOPPY**, POOR. Both GOOD and CHOPPY will fall through to the default `badge-usable` (yellow). Additionally, `LIMITED` is defined in the CSS (line 22: `badge-limited`) but is NOT a valid rating anywhere in the protocol. This is a data model mismatch between the dashboard and the core system.

Missing: `GOOD: 'badge-good'` and `CHOPPY: 'badge-choppy'` with corresponding CSS classes.

**P2 — No favicon**
The dashboard has no favicon. In a browser tab, it shows a generic icon. Minor but affects perceived polish.

### 4.2 Information Architecture

**Strengths:**
- Header: flight code, route, airline, provider, rating -- all the essential context at a glance
- Connectivity Timeline: SVG chart with signal quality, weak zone overlay, "NOW" marker -- excellent
- Status cards: API status, current phase, next event, session stats -- well-chosen metrics
- Drop log: table format with timestamp, duration, latency, packet loss -- useful for debugging

**Weaknesses:**

**P1 — "Current Phase" and "Next Event" rely on `elapsedHours()` which needs `takeoff_time`**
File: `templates/dashboard.html` line 141: `return (Date.now() - new Date(routeData.takeoff_time).getTime()) / 3600000;`
But `flight-on-lookup.sh` line 191 sets `takeoff_time: null`. The activation script (`flight-on-activate.sh`) does not set a takeoff time either. So `elapsedHours()` returns `NaN`, and the "NOW" marker, current phase, and next event calculations all break.

There is no mechanism for the user to set or for the system to detect the actual takeoff time. The dashboard timeline is essentially decorative until this is resolved.

**P1 — Live latency chart does not handle negative values**
`context-monitor.sh` sets `PING_MS=-1` and `HTTP_MS=-1` when measurements fail (lines 93-94). The dashboard renders these as data points at y-coordinate `yScale(-1)`, which would place them below the chart area. No filtering for `-1` sentinel values.
File: `templates/dashboard.html` lines 264-268.

**P2 — Elapsed time counter shows negative values before "takeoff"**
If `takeoff_time` is null or in the future, `fmtTime(Math.max(0, sec))` handles the Math.max(0,...) but the `Date.now() - new Date(null).getTime()` computation will produce a massive number (epoch time in ms), showing "620000:XX:XX" or similar nonsense.

**P2 — No session stats breakdown**
The "Session Stats" card shows `X% ctx` with `Y calls, Z reads`. This is the context monitor's rough estimate. It would be more useful to show: tasks completed, files modified, commits made -- which is the information in `.flight-state.md` but not piped to the dashboard.

### 4.3 Missing Dashboard Features

| Feature | Priority | Notes |
|---------|----------|-------|
| Takeoff time input or detection | P1 | Critical for timeline "NOW" marker and phase tracking |
| Filter -1 sentinel values from latency chart | P1 | Prevents chart rendering artifacts |
| GOOD/CHOPPY badge colors | P0 | Currently both render as USABLE (yellow) |
| Refresh interval control | P3 | Fixed at 10s; could be user-configurable |
| Manual "mark drop" button | P3 | Let user flag perceived drops |
| Export session data | P3 | Download CSV of latency/drop data |

### 4.4 Responsive Design

Minimal but present. Single media query at 768px (`templates/dashboard.html` line 45):
- Status row: 4-column to 2-column grid
- Header: row to column layout

**P2 — No mobile breakpoint below 768px.** On a phone screen (375px), the flight code is 28px, status cards are in a 2-column grid that may overflow, and the SVG charts have a fixed viewBox of 900x220 which will scale down but may be unreadable.

**P2 — Charts are not interactive on touch devices.** The tooltip uses `mouseenter`/`mouseleave` events (lines 224-236). On mobile, these don't fire. Touch users get no tooltips.

---

## 5. Documentation Quality

### 5.1 README Completeness

**Strengths:**
- Comprehensive feature overview with V2 additions
- Clear installation instructions (both local and marketplace)
- Usage examples with multiple input formats
- File structure diagram matches actual structure
- Testing instructions with individual test commands
- Protocol layer table is an excellent explainer

**Weaknesses:**

**P1 — README file structure diagram is slightly outdated**
Line 209: `run-tests.sh` is described as "Full test suite (74 core tests)" but the README header says "173 tests." The structure diagram should match reality.

**P1 — No troubleshooting section**
Common issues a user would face:
- "Port 8234 is already in use" -- how to fix
- "jq not found" -- dependency
- "Dashboard shows empty timeline" -- takeoff_time not set
- "Stop hook didn't fire" -- when does it fire and when doesn't it

**P2 — No changelog or version history**
The jump from v1 to v2 is significant. A CHANGELOG.md would help users understand what changed and why.

**P2 — No screenshots**
The dashboard is a key differentiator. Screenshots in the README would dramatically improve first impressions and help users understand what they get.

**P2 — Contributing section is empty**
"Contributing: submit a measurement" is mentioned in `data/flight-profiles.md` but there is no CONTRIBUTING.md, no measurement template, no issue template.

### 5.2 Self-Documentation

The plugin is well-self-documented:
- SKILL.md files explain each command's flow step-by-step
- Script headers explain input/output formats
- Data files have `_note` fields explaining their purpose
- hooks.json has a description field

**Gap:** The `scripts/test-monitor.sh` is undocumented in the README. It is a useful development tool but invisible to contributors.

### 5.3 Installation Instructions Quality

**P1 — No dependency list**
The plugin requires:
- `bash` (any modern version)
- `python3` (used by parse-flight.sh, network-detect.sh, flight-check.sh, flight-on-lookup.sh, flight-on-preflight.sh, context-monitor.sh)
- `jq` (used by every hook and script that reads JSON)
- `curl` (used by flight-check.sh, context-monitor.sh)
- macOS-specific: `/System/Library/PrivateFrameworks/Apple80211.framework` (network-detect.sh line 69), `networksetup` (line 74)

The README never mentions these dependencies. A user on Linux would hit immediate failures in network-detect.sh (which uses macOS-only WiFi detection). There is no Linux fallback for WiFi SSID detection.

**P1 — macOS-only network detection, no Linux support**
`scripts/network-detect.sh` uses only macOS APIs. On Linux, the SSID detection will silently return empty, and the network type will be `none`. The user gets no error -- just "Network: null (none)" in the summary.

---

## 6. Priority Matrix

### P0 — Must Fix (Broken or Misleading)

| # | Finding | File | Impact |
|---|---------|------|--------|
| P0.1 | Dashboard rating badge: GOOD and CHOPPY have no mapping, fall through to USABLE yellow. LIMITED defined but not a valid rating. | `templates/dashboard.html:126` | Every GOOD/CHOPPY flight shows wrong badge color |
| P0.2 | `/flight-off` never stops the dashboard server -- orphaned Python process | `skills/flight-off/SKILL.md` | Port 8234 stays occupied; process leak |
| P0.3 | Squash logic `grep -v "flight:" | head -1` fails when ALL commits are flight commits (empty BEFORE_FLIGHT variable) | `skills/flight-off/SKILL.md:70` | `git reset --soft` with empty arg = undefined behavior |
| P0.4 | Dashboard `takeoff_time` is always null -- "NOW" marker, elapsed time, phase tracking all broken | `scripts/flight-on-lookup.sh:191`, `templates/dashboard.html:141` | Core dashboard features non-functional |

### P1 — Should Fix (Significant UX Improvement)

| # | Finding | File | Impact |
|---|---------|------|--------|
| P1.1 | F9 (Frontier) and NK (Spirit) missing from airline-codes.json but present in profiles | `data/airline-codes.json` | These airlines' profiles are unreachable |
| P1.2 | No detection of "already active" flight mode on `/flight-on` -- overwrites state | `skills/flight-on/SKILL.md` | User loses in-progress task state |
| P1.3 | No `/flight-setup` command for first-time setup (CLAUDE.md snippet, dependency check) | — (missing skill) | Biggest adoption barrier |
| P1.4 | `flight-off` squash commit count uses `--all` flag, counting commits across all branches | `skills/flight-off/SKILL.md:23` | Inflated count, potential cross-branch squash |
| P1.5 | No post-squash verification step (`git log` to confirm result) | `skills/flight-off/SKILL.md` | Destructive operation with no confirmation |
| P1.6 | Preflight `error` field is never checked by SKILL.md instructions | `skills/flight-on/SKILL.md:13-21` | Script crashes are silently swallowed |
| P1.7 | No variant aircraft prompt for airlines with mixed fleets (UA, AA, LH, NH, etc.) | `scripts/flight-on-lookup.sh:65-76` | Conservative default may not match actual aircraft |
| P1.8 | Latency chart renders -1 sentinel values as data points | `templates/dashboard.html:264` | Chart shows nonsensical negative latency |
| P1.9 | No dependency list in README; macOS-only network detection with no Linux fallback | `README.md`, `scripts/network-detect.sh` | Linux users get silent failures |
| P1.10 | No troubleshooting section in README | `README.md` | Users hit common issues with no guidance |
| P1.11 | Multiple concurrent sessions in same repo clobber context monitor state | `scripts/context-monitor.sh:26` | State corruption |
| P1.12 | README says "74 core tests" in file tree but header says 173 | `README.md:209,233` | Documentation inconsistency |
| P1.13 | No auto-checkpoint detection on recovery (user doesn't know session was auto-saved) | `skills/flight-on/SKILL.md` | User uncertain about state integrity |

### P2 — Nice to Have (Polish)

| # | Finding | File | Impact |
|---|---------|------|--------|
| P2.1 | README lists "Option B: Marketplace" as if it works | `README.md:82-84` | Misleading for new users |
| P2.2 | Context monitor formula is undocumented and untestable | `scripts/context-monitor.sh:66-69` | Hard to validate accuracy |
| P2.3 | measure-latency.sh is orphaned (never invoked) | `scripts/measure-latency.sh` | Dead code |
| P2.4 | Dashboard elapsed time shows garbage when takeoff_time is null | `templates/dashboard.html:385-386` | Cosmetic but confusing |
| P2.5 | No favicon for dashboard | `templates/dashboard.html` | Looks unfinished |
| P2.6 | Timestamps use mixed local/UTC time across scripts | `scripts/flight-on-activate.sh:33`, `scripts/context-monitor.sh:90` | Inconsistent data |
| P2.7 | No mobile touch support for chart tooltips | `templates/dashboard.html:224-236` | Mobile users get no tooltips |
| P2.8 | No CHANGELOG.md | — | Version history invisible |
| P2.9 | No screenshots in README | `README.md` | First impression gap |
| P2.10 | Archived .flight-state files may not be gitignored if user declined initial prompt | `skills/flight-on/SKILL.md:85-98` | Clutters git status |
| P2.11 | Non-git repos get no warning about limited checkpointing | `scripts/flight-on-preflight.sh` | User expects git commits that never happen |
| P2.12 | Port collision (8234 already in use) not surfaced to user | `scripts/dashboard-server.sh` | Dashboard silently fails |
| P2.13 | User's task intent lost if included in `/flight-on` args | `scripts/parse-flight.sh` | Minor friction |
| P2.14 | No post-flight connectivity report | — | Missed feedback opportunity |

### P3 — Future Consideration

| # | Finding | File | Impact |
|---|---------|------|--------|
| P3.1 | No community contribution mechanism (measurement templates, CONTRIBUTING.md) | — | Limits organic growth |
| P3.2 | No git stash for untracked files on stop hook | `scripts/stop-checkpoint.sh` | New files can be lost |
| P3.3 | No mid-flight re-calibration based on latency degradation | `scripts/context-monitor.sh` | Protocol doesn't adapt to changing conditions |
| P3.4 | No offline mode guidance in FLIGHT_MODE.md | — | User left without instructions during total blackout |
| P3.5 | Dashboard refresh interval not configurable | `templates/dashboard.html:425` | Fixed 10s may be too frequent/infrequent |
| P3.6 | No "export session data" button on dashboard | `templates/dashboard.html` | Data lost on reboot |
| P3.7 | No `/flight-status` command for mid-session status check | — | User must open dashboard or read state file |

---

## Summary

Flight Mode v2.0.0 is an impressive and well-architected plugin. The layered protocol design is sound, the preflight orchestrator is genuinely useful, and the 40+ airline profiles represent serious research investment. The core loop of activate/work/checkpoint/recover/deactivate works.

The most urgent issues are:
1. **Dashboard data model mismatch** (P0.1) -- GOOD and CHOPPY ratings display wrong
2. **Orphaned dashboard server** (P0.2) -- process leak on deactivation
3. **Broken squash edge case** (P0.3) -- undefined behavior when all commits are flight commits
4. **Null takeoff_time** (P0.4) -- dashboard timeline features are non-functional

The biggest product gap is the **lack of a setup command** (P1.3). The manual CLAUDE.md snippet installation is the adoption bottleneck. Every user who installs this plugin should have a `/flight-setup` that handles first-run configuration automatically.

The second biggest gap is **missing airline codes** (P1.1) and **no variant aircraft prompting** (P1.7). The profile data is excellent, but the lookup pipeline has holes that prevent the right profile from being applied.

The dashboard is visually strong but functionally incomplete due to the null `takeoff_time` issue. Once that is resolved and the rating badge mapping is fixed, it becomes a genuine differentiator.
