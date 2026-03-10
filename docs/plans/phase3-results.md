# Phase 3: Expected vs Observed Behavior Report

**Date:** 2026-03-10
**Session:** 08:20 – 08:27 (7 minutes)
**Sources:** Log capture (`/tmp/flight-test-log.txt`), filesystem state, session chat logs

---

## Timeline Reconstruction

| Time | Event |
|------|-------|
| 08:20:09 | Log capture started. Repo: 1 commit ("init"). Dashboard DOWN. |
| 08:21:04 | Dashboard UP (HTTP 200). route-data.json: CX, HKG-LAX, USABLE, 16 waypoints, weak_zone 5-8 |
| ~08:21 | **Test A:** `/flight-on CX HKG-LAX` → summary shown → user says "n" → no activation |
| ~08:22 | **Test B:** `/flight-on` (no args) → asks for flight → user gives "CX884" → summary → user says "y" |
| 08:24:17 | **Test C (activation):** FLIGHT_MODE.md + .flight-state.md created |
| 08:24:59 | .gitignore created (3 entries) |
| ~08:25 | Claude asks "What do you want to work on?" → user runs `/flight-off` instead |
| 08:25:54 | .flight-state.md archived → .flight-state-2026-03-10.md |
| 08:25:56 | FLIGHT_MODE.md removed |
| 08:27:13 | Log capture stopped. Final state clean. |

**Note:** User combined Tests B and C — said "y" to Test B's activation gate instead of "n", making that the activation for Test C. Valid flow.

---

## Test A: `/flight-on CX HKG-LAX` + Decline

| # | Check | Expected | Observed | Status |
|---|-------|----------|----------|--------|
| 1 | Preflight runs deterministically | `!`command`` injects JSON | Dashboard started at 08:21:04, summary appeared immediately | PASS |
| 2 | Claude skips to summary (ready=true) | No questions asked about flight | Went straight to summary | PASS |
| 3 | Airline correct | Cathay Pacific CX | "Cathay Pacific CX" | PASS |
| 4 | Route correct | HKG → LAX (~13h) | "HKG → LAX (~13h)" | PASS |
| 5 | Rating correct | USABLE | "USABLE" | PASS |
| 6 | Provider correct | gogo | "Gogo" (capitalized — cosmetic) | PASS |
| 7 | API verdict | GO via US | "GO via US" | PASS |
| 8 | Network shown | ssid or "no WiFi" | "No WiFi connected yet" | PASS |
| 9 | Dashboard URL | http://localhost:8234 | "http://localhost:8234" | PASS |
| 10 | Calibration | 1-2 batch, 2-3 checkpoint, 2-3 commit | Exactly that | PASS |
| 11 | Weak zone | Hours 5-8, reason text | "Hours 5-8: WEAK ZONE — Sparse GEO beams over central North Pacific, farthest from any ground station" | PASS |
| 12 | Connectivity timeline | 3 phases (strong/weak/recovery) | "Hours 0-5: Strong signal (HKG → past Japan)" + weak + recovery | PASS |
| 13 | Hard gate asked | "Activate flight mode? (y/n)" | "Activate flight mode? (y/n)" | PASS |
| 14 | "n" respected | No activation, no files created | "Flight mode not activated. Dashboard is live at http://localhost:8234." | PASS |
| 15 | No FLIGHT_MODE.md | absent | absent (log confirms through 08:24) | PASS |
| 16 | No .flight-state.md | absent | absent (log confirms through 08:24) | PASS |
| 17 | Dashboard alive | HTTP 200 | UP throughout | PASS |
| 18 | route-data.json correct | CX/HKG-LAX/USABLE/16wp/wz5-8 | Exactly that (log: 2351B) | PASS |

**Test A: 18/18 PASS**

---

## Test B: `/flight-on` with no args

| # | Check | Expected | Observed | Status |
|---|-------|----------|----------|--------|
| 1 | ready=false detected | Claude reads missing array | "Preflight shows ready: false — missing airline and route info." | PASS |
| 2 | ONE question asked | Single question for airline + route | "What flight are you on? (e.g., CX624 HKG-LAX)" | PASS |
| 3 | User gives partial info | needs_route=true for flight code only | User gave "CX884" (flight code, no route) | — |
| 4 | Claude fills route gap | Should ask for route (missing=["route"]) | Claude inferred HKG-LAX from CX884 world knowledge, ran lookup without asking | DEVIATION |
| 5 | Lookup script executed | flight-on-lookup.sh via Bash | Yes — Bash command visible with CX, HKG, LAX params | PASS |
| 6 | Summary shown | Correct data from lookup | CX884, HKG → LAX (~13h), Gogo, USABLE, GO via US | PASS |
| 7 | Weak zone shown | Hours 5-8 | "Hours 5-8: WEAK ZONE — Sparse GEO beams over central North Pacific" | PASS |
| 8 | Calibration correct | USABLE: 1-2 batch, 2-3 checkpoint | Exactly that | PASS |
| 9 | Hard gate asked | "Activate? (y/n)" | "Activate flight mode? (y/n)" | PASS |
| 10 | Dashboard still running | UP from Test A | No state change logged (stayed UP) | PASS |

**Test B: 9/10 PASS, 1 DEVIATION**

### Deviation Detail: Route inference (check #4)

- **Expected:** After user says "CX884", parse-flight.sh returns `needs_route: true`. Per SKILL.md Step 2, Claude should ask: *"What's the route? (e.g., BLR-HKG)"*
- **Observed:** Claude used world knowledge to infer CX884 = HKG→LAX and ran the lookup directly without asking for the route.
- **Impact:** Low — the route was correct. Claude was being helpful. But it bypassed the mechanical "ask for missing info" step in the skill protocol.
- **Severity:** Minor. The deterministic preflight correctly identified `missing: ["route"]`. Claude's thin layer made an LLM judgment call to fill it from world knowledge rather than asking. This is borderline — the skill says "Ask the user ONE question to fill the gaps" but Claude already had the answer.
- **Action:** Consider whether the skill should say "ALWAYS ask, even if you think you know" or whether inference is acceptable. For v2.0.0, this is fine.

### Not tested: GOOD rating path

The expected behavior suggested testing with "DL JFK-LAX" to verify the GOOD rating renders differently from USABLE. Since the user gave "CX884" (USABLE), the GOOD rating path was not exercised in live testing. Phase 2 smoke tests confirmed GOOD rating returns correct data from the lookup script.

---

## Test C: `/flight-on CX HKG-LAX` + Accept + `/flight-off`

### Activation

| # | Check | Expected | Observed | Status |
|---|-------|----------|----------|--------|
| 1 | Hard gate before activation | "Activate? (y/n)" | Asked at end of Test B summary, user said "y" | PASS |
| 2 | Activate script used | Bash → flight-on-activate.sh | Bash command visible with full JSON payload | PASS |
| 3 | Activation confirmed | "Flight mode activated" | "Flight mode activated. Now checking .gitignore." | PASS |
| 4 | FLIGHT_MODE.md created | exists, correct content | 08:24:17 — 21 lines, CX, HKG→LAX, USABLE, gogo | PASS |
| 5 | .flight-state.md created | exists, session header | 08:24:17 — 22 lines | PASS |
| 6 | .gitignore check | Offered since none exists | "No .gitignore exists in this repo." + offer with 3 entries | PASS |
| 7 | .gitignore created | 3 entries | 08:24:59 — FLIGHT_MODE.md, .flight-state.md, .flight-state-*.md | PASS |
| 8 | Task prompt | "What do you want to work on this flight?" | "What do you want to work on this flight?" | PASS |

### /flight-off

| # | Check | Expected | Observed | Status |
|---|-------|----------|----------|--------|
| 9 | Reads state files | FLIGHT_MODE.md + .flight-state.md | "Read 2 files" | PASS |
| 10 | Counts flight commits | git log grep "flight:" | Bash: `git log --oneline --all \| grep "flight:" \| wc -l` → 0 | PASS |
| 11 | Summary shown | Airline, rating, session time, tasks, commits | Correct: CX HKG-LAX, USABLE, 08:24→now, 0/0 tasks, 0 commits | PASS |
| 12 | Tasks count accurate | 0/0 (no tasks assigned) | "Tasks: 0/0 completed (no tasks were assigned)" | PASS |
| 13 | Squash correctly skipped | Skip for 0-1 commits | "No flight commits to squash. Cleaning up." | PASS |
| 14 | State archived | mv .flight-state.md → dated | 08:25:54 — renamed to .flight-state-2026-03-10.md | PASS |
| 15 | FLIGHT_MODE.md removed | rm FLIGHT_MODE.md | 08:25:56 — removed | PASS |
| 16 | Confirmation | "Flight mode off" | "Flight mode off. Back to normal operations." | PASS |
| 17 | Dashboard survives | Still UP (known gap) | HTTP 200, PID alive at end | PASS |

**Test C: 17/17 PASS**

---

## Final State Verification

| Item | Expected | Observed | Status |
|------|----------|----------|--------|
| FLIGHT_MODE.md | ABSENT | ABSENT | PASS |
| .flight-state.md | ABSENT | ABSENT | PASS |
| .flight-state-2026-03-10.md | EXISTS | EXISTS (502 bytes) | PASS |
| .gitignore | EXISTS (3 entries) | EXISTS (correct content) | PASS |
| Dashboard HTTP | UP (200) | UP (200) | PASS |
| Dashboard server PID | ALIVE | PID 37239 ALIVE | PASS |
| route-data.json | CX/HKG-LAX/USABLE/16wp/wz5-8 | Exactly that | PASS |
| Dashboard dir files | index.html, route-data.json, live-data.json, server.pid | All present | PASS |
| Git commits | "init" only (no work done) | "init" only | PASS |

---

## Summary Scorecard

### All checks combined: 44 evaluated + 1 deviation

| Test | Checks | Pass | Deviation | Fail | Skipped |
|------|--------|------|-----------|------|---------|
| A: flight-on + decline | 18 | 18 | 0 | 0 | 0 |
| B: flight-on no args | 10 | 9 | 1 | 0 | 0 |
| C: activate + flight-off | 17 | 17 | 0 | 0 | 0 |
| Final state | 9 | 9 | 0 | 0 | 0 |
| **Total** | **54** | **53** | **1** | **0** | **0** |

### The 1 deviation

**Route inference bypass** — Claude inferred CX884 = HKG→LAX from world knowledge instead of asking the user for the missing route. Not a failure (correct result), but bypasses the skill protocol's "ask for missing info" step. Minor — acceptable for v2.0.0.

### Untested paths

These were not exercised due to user going directly from activation to /flight-off:

| Path | Why untested | Risk | Covered by |
|------|-------------|------|------------|
| Micro-task decomposition | No task given | Low | Skill prompt is explicit |
| .flight-state.md updates during work | No work done | Low | Script creates correct template |
| `flight:` commit creation | No work done | Low | Stop hook tested in Phase 1 |
| Checkpoint intervals | No work done | Low | Protocol is in FLIGHT_MODE.md |
| Commit squash (/flight-off) | 0 commits to squash | Medium | Non-interactive approach tested in Phase 1 |
| GOOD rating live display | User used CX not DL | Low | Phase 2 smoke test confirmed GOOD from lookup |
| Context monitor warnings | Session too short | Low | Phase 1 tested all thresholds |
| Stop hook auto-checkpoint | /flight-off ran first | Low | Phase 1 tested with uncommitted changes |
| PreToolUse hook live block | Claude didn't attempt direct write | Low | Phase 2 tested deny/allow |

---

## Known Issues

### Minor
1. **Log capture spam** — "Flight state archived" repeats every poll after /flight-off (log script bug, not plugin bug)
2. **Provider capitalization** — Skill shows "Gogo" (capitalized by Claude), data has "gogo" (lowercase). Cosmetic.

### Tracked (backlog)
1. **Dashboard server lifecycle** — Not auto-stopped on /flight-off. Notion item created (Sprint 3).
