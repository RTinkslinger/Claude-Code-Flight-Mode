# Hook Run Order Reference

> **Key fact:** Hooks within the same event run in **parallel** (per Claude Code docs).
> Order cannot be enforced. Design all hooks to be idempotent and order-independent.

## Two Hook Sources

| Source | Config Location | Scope |
|---|---|---|
| CASH Build System | `.claude/settings.local.json` (project) | Development discipline |
| Flight Mode Plugin | `hooks/hooks.json` (plugin) | Network resilience |

Plugin hooks merge with project hooks and run in parallel.

## Event Map

### SessionStart
```
[CASH] startup → echo REQUIRED directive (read TRACES, check Roadmap)
[CASH] compact → sed TRACES.md header (re-inject after compaction)
```
No flight mode hooks. No conflict.

### PreToolUse
```
[CASH] Agent    → prompt: 4-block subagent validation
[CASH] Edit|Write → command: check-sequential-files.sh (advisory warning)
```
No flight mode hooks. No conflict.

### PostToolUse
```
[Flight Mode] Read|Edit|Write|Bash|Grep|Glob → command: context-monitor.sh
```
No CASH hooks on this event. No conflict.

### PostToolUseFailure
```
[CASH] Bash|Edit|Write → prompt: LEARNINGS.md capture nudge
```
No flight mode hooks. No conflict.

### Stop (PARALLEL — both fire simultaneously)
```
[CASH]         → command: stop-check.sh (exit 2 if code changed + TRACES stale)
[Flight Mode]  → command: stop-checkpoint.sh (auto-commit uncommitted changes)
```

**Race condition analysis:**
- Both read git status simultaneously
- CASH checks: code files modified? TRACES.md recently updated?
- Flight Mode checks: uncommitted changes? If yes, commit them.
- If ANY hook exits 2, Claude continues (blocked from stopping)

**All scenarios converge correctly:**
1. CASH blocks (exit 2) → Claude updates TRACES → next Stop: both exit 0
2. CASH allows (exit 0) + Flight Mode allows (exit 0) → Claude stops
3. `stop_hook_active` guard prevents infinite loops on second+ firing

**Design invariant:** Both hooks are idempotent. Any order produces same end state.

## Compatibility Rules for Adding Future Hooks

1. **Same event, different matchers** → always safe (e.g., PreToolUse on `Agent` vs `Edit|Write`)
2. **Same event, same matcher** → must be idempotent and order-independent
3. **Stop hooks** → must handle `stop_hook_active` to prevent loops
4. **Never rely on one hook's side effects being visible to another** — they run in parallel
5. **Exit 2 from ANY hook in an event blocks the action** — design conservatively
