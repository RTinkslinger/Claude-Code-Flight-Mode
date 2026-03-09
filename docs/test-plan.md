# Flight Mode Plugin — Test Plan

## Test Categories

### T1: Activation Flow (`/flight-on`)

| ID | Test | Expected |
|---|---|---|
| T1.1 | Activate with known carrier (e.g., "Cathay Pacific HKG-LAX") | Finds profile, shows USABLE rating, creates FLIGHT_MODE.md + .flight-state.md |
| T1.2 | Activate with unknown carrier (e.g., "Garuda Indonesia DPS-SIN") | Falls back to UNKNOWN/USABLE, notes carrier not profiled |
| T1.3 | Activate with carrier that has multiple ratings (e.g., "United") | Asks to clarify aircraft type or defaults based on route |
| T1.4 | Activate when FLIGHT_MODE.md already exists | Detects existing session, asks to resume or restart |
| T1.5 | Activate when .flight-state.md has incomplete tasks | Offers to resume from last checkpoint |
| T1.6 | Activate in repo without .gitignore entries | Suggests adding runtime files to .gitignore |
| T1.7 | Activate in repo without git | Still works — checkpoint file is the only safety net, warns user |
| T1.8 | Task decomposition after activation | Decomposes user request into numbered micro-tasks, writes to .flight-state.md, confirms before starting |

### T2: Deactivation Flow (`/flight-off`)

| ID | Test | Expected |
|---|---|---|
| T2.1 | Deactivate with all tasks complete | Summary of completed work, offers squash, cleans up |
| T2.2 | Deactivate with incomplete tasks | Notes remaining tasks clearly for normal-session pickup |
| T2.3 | Squash flight commits (accept) | Non-interactive squash via `git reset --soft`, single new commit |
| T2.4 | Squash flight commits (decline) | Leaves `flight:` commits as-is |
| T2.5 | Deactivate when no flight commits exist | Skips squash offer, proceeds to cleanup |
| T2.6 | Archive .flight-state.md | Renamed to `.flight-state-YYYY-MM-DD.md`, FLIGHT_MODE.md deleted |

### T3: Checkpoint Protocol

| ID | Test | Expected |
|---|---|---|
| T3.1 | USABLE rating: checkpoint cadence | .flight-state.md updated every 2-3 micro-tasks |
| T3.2 | EXCELLENT rating: checkpoint cadence | Every 4-5 micro-tasks |
| T3.3 | POOR rating: checkpoint cadence | After every micro-task |
| T3.4 | .flight-state.md has valid recovery instructions | A fresh session can read it cold and resume accurately |
| T3.5 | Git commits use `flight:` prefix | All commits during flight mode match pattern |
| T3.6 | Commits stage specific files (not `git add -A`) | Only modified files are staged |

### T4: Session Recovery (the critical path)

| ID | Test | Expected |
|---|---|---|
| T4.1 | Kill terminal mid-task, start new session | New session reads FLIGHT_MODE.md → .flight-state.md → resumes from last incomplete task |
| T4.2 | Recovery with uncommitted changes (stop hook) | Stop hook auto-commits before session dies |
| T4.3 | Recovery without CLAUDE.md snippet installed | Hooks still fire (graceful degradation), but no auto-detection of FLIGHT_MODE.md |
| T4.4 | Recovery with clean git state | Resumes from .flight-state.md task list, no git conflicts |
| T4.5 | Multiple drops in one flight | Each recovery picks up cleanly, no accumulated state corruption |

### T5: Stop Hook (`stop-checkpoint.sh`)

| ID | Test | Expected |
|---|---|---|
| T5.1 | Session ends with uncommitted changes + FLIGHT_MODE.md exists | Hook commits with `flight: auto-checkpoint on session end` |
| T5.2 | Session ends with clean working tree | Hook exits silently (exit 0) |
| T5.3 | Session ends without FLIGHT_MODE.md | Hook exits immediately (no-op) |
| T5.4 | Hook runs in non-git directory | Fails gracefully, no error output |
| T5.5 | Hook timeout | Completes within 15s timeout |

### T6: Context Monitor Hook (`context-monitor.sh`)

| ID | Test | Expected |
|---|---|---|
| T6.1 | Below 40% estimated usage | Silent — no output, zero context overhead |
| T6.2 | 40-60% estimated usage | Injects "~50% context. Consider checkpointing." |
| T6.3 | 60-80% estimated usage | Injects "~70% context. Checkpoint NOW." |
| T6.4 | 80%+ estimated usage | Injects "STOP. Suggest new session." |
| T6.5 | Hook called without FLIGHT_MODE.md | Exits immediately (no-op) |
| T6.6 | State file persistence across tool calls | Counter increments correctly across calls |
| T6.7 | Hook timeout | Completes within 5s timeout |
| T6.8 | Counters reset between sessions | New session starts fresh counters |

### T7: Profile Lookup

| ID | Test | Expected |
|---|---|---|
| T7.1 | Exact carrier match | Returns correct rating + stable window |
| T7.2 | Carrier with domestic vs long-haul split | Returns appropriate rating for route type |
| T7.3 | Unknown carrier | Returns USABLE defaults |
| T7.4 | Route pattern match (e.g., "transpacific") | Supplements carrier data with route pattern notes |

### T8: Edge Cases

| ID | Test | Expected |
|---|---|---|
| T8.1 | Activate twice without deactivating | Second activation detects existing, handles gracefully |
| T8.2 | Deactivate when not activated | Reports "flight mode not active" |
| T8.3 | Very long session (100+ tool calls) | Context monitor escalates warnings appropriately |
| T8.4 | Pre-commit hook failure during flight commit | Notes failure, skips commit, continues work |
| T8.5 | Plugin loaded but jq not installed | Hooks fail gracefully with meaningful error |
| T8.6 | Concurrent .flight-state.md reads/writes | No corruption (single-session, sequential access) |

---

## Test Execution Approach

**Manual testing during development:**
```bash
# Test plugin loading
claude --plugin-dir . --debug

# Test hook scripts standalone
echo '{"tool_name":"Read","tool_input":{"file_path":"test.js"}}' | bash scripts/context-monitor.sh
echo '{}' | bash scripts/stop-checkpoint.sh

# Validate JSON
jq . hooks/hooks.json
```

**End-to-end test (Phase 3):**
1. Install plugin: `claude --plugin-dir .`
2. `/flight-on` → Cathay Pacific HKG-LAX
3. Request: "Add a comment to CLAUDE.md"
4. Execute 3-4 micro-tasks
5. Kill terminal (simulate drop)
6. New session: verify recovery from .flight-state.md
7. Complete remaining tasks
8. `/flight-off` → verify summary + squash offer
