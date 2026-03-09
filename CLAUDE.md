# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flight Mode is a publishable Claude Code **plugin** that makes Claude resilient on unreliable in-flight WiFi. It installs globally and works across all repos. It changes **how Claude thinks** (micro-tasks, checkpointing, context budgeting) rather than switching models.

## Plugin Structure

```
flight-mode/
├── .claude-plugin/
│   └── plugin.json                  # Plugin manifest
├── skills/
│   ├── flight-on/
│   │   └── SKILL.md                 # /flight-on activation
│   └── flight-off/
│       └── SKILL.md                 # /flight-off deactivation
├── hooks/
│   └── hooks.json                   # Stop + PostToolUse hooks
├── scripts/
│   ├── stop-checkpoint.sh           # Auto-commit on session end
│   └── context-monitor.sh           # Track context usage, inject warnings
├── data/
│   └── flight-profiles.md           # Airline WiFi lookup (compact table + reference)
├── templates/
│   └── claude-md-snippet.md         # 3-line CLAUDE.md addition for users
├── README.md
├── LICENSE
└── docs/
    ├── system-plan-v2.md            # Current system plan (V2)
    ├── plugin-reference.md          # Plugin/hooks dev reference
    └── start point - from cowork/   # Original research materials
```

## Architecture: Layered Protocol (Option C)

The behavioral protocol is split across four layers:

1. **Skill prompt** (`/flight-on` SKILL.md) — full verbose protocol, injected once at activation
2. **FLIGHT_MODE.md** (generated in user's repo) — airline, rating, condensed protocol (~20 lines); read on recovery
3. **CLAUDE.md snippet** (user's global config) — 3 lines: "read FLIGHT_MODE.md if it exists"
4. **Hooks** — Stop hook auto-checkpoints; PostToolUse hook monitors context budget

Each layer does one job. No duplication. Hooks enforce mechanically, protocol text covers what hooks can't.

## Key Design Decisions

- **Plugin, not loose files** — uses Claude Code plugin system (plugin.json, skills, hooks)
- **Global installation** — works across all repos without per-repo setup
- **Rating scale drives behavior** — EXCELLENT→POOR calibrates checkpoint/commit frequency
- **Checkpoints at intervals, not every task** — rating-calibrated, Stop hook as safety net
- **Context budget via PostToolUse hook** — tracks tool calls + file reads, injects warnings at thresholds
- **Git commits use `flight:` prefix** — specific file staging (not `git add -A`), pre-commit hook aware
- **Non-interactive commit squash** — `git reset --soft` approach (no `rebase -i`)
- **Profiles have compact lookup table** — Claude reads ~30 lines, not 389

## Build Phases

See `docs/system-plan-v2.md` for full plan. Summary:

- **Phase 1:** Plugin scaffold, `/flight-on` skill, `/flight-off` skill, profiles data, templates
- **Phase 2:** hooks.json, stop-checkpoint.sh, context-monitor.sh, testing
- **Phase 3:** README, LICENSE, end-to-end testing, publish

## Development Commands

```bash
# Test plugin during development
claude --plugin-dir . --debug

# Validate hooks.json
jq . hooks/hooks.json

# Test a hook script
echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash scripts/context-monitor.sh

# Review loaded hooks in a Claude session
/hooks
```

## Reference Docs

- `docs/system-plan-v2.md` — full V2 plan with protocol, hook designs, phase breakdown
- `docs/plugin-reference.md` — plugin.json schema, hook events, exit codes, JSON output formats
- `docs/start point - from cowork/flight-profiles.md` — raw research data (40+ carriers)
- `docs/start point - from cowork/flight-mode-system-plan.md` — original V1 plan (superseded)
