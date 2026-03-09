# Milestone 1: Core Plugin + V2 Feature Build
**Iterations:** 1-3 | **Dates:** 2026-03-10

## Summary
Built the complete Flight Mode plugin from scratch: core plugin structure (Phase 1+2), live flight testing with bug fix, and the full V2 feature set (flight parsing, network detection, API geo-checking, live dashboard, route connectivity timelines). Total: 173 tests passing, 6 data files, 6 scripts, 3 skills, 1 dashboard.

## Key Decisions
- Option C layered protocol (skill→FLIGHT_MODE.md→snippet→hooks) — each layer does one job
- Flag-file activation pattern (`[ -f FLIGHT_MODE.md ] || exit 0`) — hooks are true no-ops when inactive
- Country determined by satellite ground station PoP, not aircraft location — airport WiFi geo-blocked, airline WiFi usually safe
- Starlink ISL routing = high risk (unpredictable egress country)
- Dashboard on localhost:8234 with 10s polling
- Parse-flight uses embedded Python for regex/JSON across 6 input strategies
- Latency measurements every 3rd tool call for minimal overhead

## Iteration Details

### Iteration 1 - 2026-03-10
**Phase:** Phase 1+2: Core Plugin Build
**Focus:** Full plugin scaffold, skills, hooks, scripts, tests

**Changes:** `.claude-plugin/plugin.json` (manifest), `skills/flight-on/SKILL.md` (8-step activation, 7 rules, calibration), `skills/flight-off/SKILL.md` (8-step deactivation, squash), `hooks/hooks.json` (Stop + PostToolUse), `scripts/stop-checkpoint.sh` (auto-commit on drop), `scripts/context-monitor.sh` (budget tracking 45/65/85%), `data/flight-profiles.md` (40+ carriers), `templates/claude-md-snippet.md`, `tests/run-tests.sh` (74 tests), `tests/live-simulation.sh` (22 tests), `scripts/measure-latency.sh`, `docs/in-flight-test-plan.md`
**Decisions:** Option C layered protocol -> each layer does one job, no duplication. Flag-file activation -> hooks are true no-ops when inactive. `set -uo pipefail` not `-euo` -> grep exit-1 kills script with pipefail+errexit.

### Iteration 2 - 2026-03-10
**Phase:** Phase 2: Live Testing + Bug Fix
**Focus:** Live flight WiFi test + .flight-state.md timing bug fix

**Changes:** `skills/flight-on/SKILL.md` (added Step 4b), `measurements/2026-03-10-cathay-hkg-lax.csv`
**Decisions:** Create .flight-state.md in Step 4b before task decomposition -> recovery works even if killed during setup steps 1-6.

### Iteration 3 - 2026-03-10
**Phase:** V2: Full Feature Build
**Focus:** Flight parsing, network detection, API geo-check, dashboard, route corridors, comprehensive tests

**Changes:** 6 data files, 4 new scripts, dashboard-server.sh, context-monitor.sh update, dashboard.html, flight-on SKILL.md rewrite, flight-check SKILL.md new, plugin.json v2.0.0, 5 new test files (99 tests)
**Decisions:** Country = satellite ground station PoP. Starlink = high risk. Dashboard on localhost:8234. Parse-flight embedded Python. Latency every 3rd call.
