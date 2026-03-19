# Iteration 1 — Synthesis: Cross-Team Findings

**Date:** 2026-03-18
**Auditors:** Product Lead, Backend Engineer, Frontend Engineer, QA Lead
**Baseline:** 173 tests, all passing. v2.0.0 tagged.

---

## Deduplicated P0/Critical Issues (Must Fix)

| # | Finding | Confirmed By | Root Cause |
|---|---------|-------------|------------|
| C1 | `set -euo pipefail` in context-monitor.sh — silent failure on every tool call | Backend | Line 5: `-e` flag causes script to exit on any non-zero command |
| C2 | Dashboard rating badge: GOOD/CHOPPY have no CSS mapping | Product, Frontend | `dashboard.html:126` — only maps EXCELLENT, USABLE, LIMITED, POOR |
| C3 | `takeoff_time` always null — dashboard NOW marker, elapsed, phase all broken | Product, Frontend | `flight-on-lookup.sh:191` sets `None`, never populated |
| C4 | Empty waypoints array crashes `updateStatusCards` | Frontend | `dashboard.html:333` — `wp[0]` undefined when waypoints=[] |
| C5 | Squash logic broken for interleaved/all-flight commits | Product, Backend, QA | `flight-off SKILL.md:70` — `grep -v | head -1` logic is fundamentally wrong |
| C6 | `/flight-off` never stops dashboard server | Product | `flight-off SKILL.md` — no step calls `dashboard-server.sh stop` |
| C7 | JSON injection in `flight-on-preflight.sh` | Backend | Lines 17-57 — raw user input interpolated into JSON strings |
| C8 | Negative latency sentinel values (-1) render below chart | Product, Frontend | `dashboard.html:264` — no filter for -1 values from context-monitor.sh |

## P1 Issues Selected for Iteration 2

| # | Finding | File(s) |
|---|---------|---------|
| H1 | `ping -W` portability — macOS milliseconds vs Linux seconds | flight-check.sh, context-monitor.sh |
| H2 | PostToolUse hook timeout too tight (5s) for network calls | hooks.json |
| H3 | Non-atomic state file writes in context-monitor.sh | context-monitor.sh |
| H4 | Missing airline codes F9 (Frontier), NK (Spirit) | airline-codes.json |
| H5 | renderTimeline rebuilds entire SVG every 1 second | dashboard.html |
| H6 | fetchRoute only called once — never re-fetched | dashboard.html |
| H7 | Empty catch blocks swallow errors silently | dashboard.html |
| H8 | No "already active" detection on /flight-on | flight-on SKILL.md |
| H9 | `routeData = {}` is truthy but .waypoints is undefined | dashboard.html |
| H10 | Hash length inconsistency md5 (32 chars) vs md5sum (12 chars) | context-monitor.sh, dashboard-server.sh |
| H11 | dashboard-server.sh uses `cd` instead of `--directory` flag | dashboard-server.sh |

## Test Coverage Gap (from QA)

- **5 scripts with ZERO tests** (F grade): lookup, preflight, activate, dashboard-server, block-direct
- **~35% critical path coverage** overall
- **No integration tests** exist
- **Squash logic never tested** with real git history

## Iteration 2 Plan

4 agents dispatched in parallel:

1. **Backend Fix Agent** — C1, C7, H1, H2, H3, H10, H11
2. **Frontend Fix Agent** — C2, C3, C4, C8, H5, H6, H7, H9
3. **Skill & Data Fix Agent** — C5, C6, H4, H8
4. **Test Agent** — Write tests for lookup, activate, block-direct, squash, preflight
