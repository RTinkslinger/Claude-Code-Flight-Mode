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

---

## Build System Protocol

### Build Traces (MANDATORY)

Track implementation decisions with minimal context overhead using a rolling window + compaction pattern.

**IMPORTANT:** Enforced by a Stop hook — if you modify code files but don't update TRACES.md, the hook will prevent you from stopping and require you to update TRACES.md first.

#### Quick Reference

| File | Purpose | When to Read |
|------|---------|--------------|
| `TRACES.md` | Rolling window (~80 lines) | Start of every coding session + before closing |
| `traces/archive/milestone-N.md` | Full historical detail | Only when debugging or researching past decisions |

#### What Counts as an Iteration

An iteration is a work session where you:
- Write or modify code files (not specs/docs)
- Complete tasks from the phase plan
- Make architectural or implementation decisions

**Scope rule:** One iteration = one focus area. If you worked on 3 different things,
that's 3 iterations, not 1. A good test: can you describe the focus in 5 words?

NOT an iteration: Pure research, Q&A, planning, or documentation-only changes.

#### After Each Coding Session (or before Session Close)

1. **Read `TRACES.md`** - find the last iteration number in "Current Work"
2. **Add iteration entry** to "Current Work" section (template below)
3. **If iteration 3, 6, 9...** -> run compaction process (see below)

#### Iteration Entry Template (Concise ~15 lines)

```
### Iteration N - YYYY-MM-DD
**Phase:** Phase X: Name
**Focus:** Brief description

**Changes:** `file.py` (what), `other.py` (what)
**Decisions:** Key decision -> rationale
**Next:** What's next

---
```

#### Compaction Process (Every 3 Iterations)

When you complete iteration 3, 6, 9, 12..., perform these steps:

1. **Create archive file** `traces/archive/milestone-N.md`:
   ```
   # Milestone N: [Focus Area]
   **Iterations:** X-Y | **Dates:** YYYY-MM-DD to YYYY-MM-DD

   ## Summary
   [2-3 sentences on what was accomplished]

   ## Key Decisions
   - Decision 1: Rationale
   - Decision 2: Rationale

   ## Iteration Details
   [Copy all 3 iteration entries from Current Work]
   ```

2. **Update Project Summary** in TRACES.md - add key decisions from this milestone
3. **Update Milestone Index** - add one row to the table
4. **Clear Current Work** - remove the 3 archived iterations, keep section header

#### When to Read Archive Files

Only read `traces/archive/` if:
- User asks about historical decisions
- Debugging requires understanding why something was built a certain way
- You need context from a specific past milestone

**Do NOT read archive files during normal iteration updates.**

### Branch Lifecycle

**Scope:** Applies to project source code changes — files that implement features, fix bugs,
or modify application behavior. Does NOT apply to:
- Build system setup (TRACES.md, LEARNINGS.md, CLAUDE.md, hooks, settings.json)
- Documentation-only changes (README, docs/, .md files not in src/)
- Global config files outside the project (~/.claude/*, ~/.mcp.json)

When in doubt: if the change could break the application, use a branch.

Every code change follows: CREATE > WORK > REVIEW > SHIP

- **CREATE** — `git checkout -b {feat|fix|research|infra}/slug` from main.
  Update Build Roadmap: Status = In Progress, Branch = branch name.
- **WORK** — Edit, commit, iterate. Keep changes scoped (1-2 files ideal, single concern).
- **REVIEW** — `git diff main..branch` — review all changes before merge. This is the quality gate.
- **SHIP** — `git checkout main && git merge branch && git branch -d branch`.
  Update Roadmap: Status = Verifying, Branch = clear.
- **VERIFY** — User tests outside Claude Code. On next session, SessionStart hook asks about
  Verifying items. Pass = Shipped. Fail = spawn fix/ item with Source = Verification Failure.

### Build Roadmap

- **Notion DB Data Source ID:** bf79137a-3a67-457c-84ce-3578f13c32b7
- **Default View URL:** https://www.notion.so/0f822d11af47441992c8491e502d70e3

**Real-time updates (not batch-at-end):**
- Start working on item > update to In Progress immediately
- Ship (merge to main) > update to Verifying immediately
- Discover insight mid-session > create Insight item immediately
- Every code change must have a Roadmap item. If none exists, create one before starting.
  - Exception: Build system infrastructure setup (creating TRACES.md, LEARNINGS.md,
    configuring hooks) does not require a Roadmap item — it IS the system that creates Roadmap items.

**Auto-filled fields:** Priority, Technical Notes (medium depth — implementation approach,
key dependencies, why it matters), Parallel Safety (via 3-tier heuristic), Sprint#,
Source, Task Breakdown (populated when item moves to In Progress).

**Reading the Roadmap:**
```
notion-query-database-view with view_url: "https://www.notion.so/0f822d11af47441992c8491e502d70e3"
```

**Creating items:**
```
notion-create-pages with parent: { data_source_id: "bf79137a-3a67-457c-84ce-3578f13c32b7" }
properties: {
  "Item": "Description",
  "Status": "Insight",
  "Priority": "[auto-assessed]",
  "Epic": "[from standard set]",
  "Source": "[category]",
  "Sprint#": [current sprint number],
  "Technical Notes": "[auto-filled context]",
  "Parallel Safety": "[auto-classified]"
}
```

### Sprint System

- Sprint# = current TRACES.md milestone being worked toward
- Sprint N = all work between Milestone N-1 and Milestone N
- Find current sprint: read TRACES.md > last milestone number + 1
- Items discovered during Sprint N get tagged Sprint# = N
- "What shipped in Sprint 3?" = query Roadmap: Sprint# = 3, Status = Shipped

### Subagent Protocol

Every Agent call must include 4 blocks:

1. **CONSTRAINTS** — What the subagent cannot do: no MCP tools, no git operations,
   no network access, no files outside the allowlist below.
2. **FILE ALLOWLIST** — Every file the subagent may Read/Edit/Write, explicitly listed.
   "Do NOT touch any files not on this list."
3. **TASK** — Specific instructions with enough context to work independently.
4. **SUCCESS CRITERIA** — What "done" looks like so the subagent can self-validate.

**Parallel delegation pattern (for breaking big changes into multiple subagents):**
1. DECOMPOSE — Analyze the change, identify independent subtasks
2. MAP FILES — Assign each subtask an explicit file allowlist with ZERO overlap
3. PARALLEL SPAWN — Multiple Agent calls, each with all 4 blocks
4. REVIEW — Main session reviews all outputs for consistency
5. COMMIT — Main session commits the combined changes

### File Classification (Parallel Safety)

Before parallel work (multi-tab or multi-subagent), classify target files:
- **Safe** — New files, isolated files (0-1 importers), docs, research
- **Coordinate** — Shared files with 2-4 importers across the codebase
- **Sequential** — Config files, shared type definitions, files with 5+ importers

**Auto-classification heuristic:**
1. Pattern match on item description ("new file" = Safe, "schema change" = Sequential)
2. If ambiguous: Grep for imports/references to target file, count fan-out
3. Check known critical files list below

**Known critical (Sequential) files for this project:**
Maintained in `.claude/sequential-files.txt` (one filename per line).
Initial: `CLAUDE.md`. Add files when parallel edits cause merge conflicts.
The PreToolUse hook reads this file and warns subagents — it never blocks edits.

Task safety = worst classification of any file it touches. Default = Coordinate if uncertain.

### LEARNINGS.md Protocol

- When you try a method, it fails, and you succeed with a different method:
  immediately log the broken > working pair to LEARNINGS.md before continuing.
- Don't wait for session end. Capture at the moment of discovery.
- During TRACES.md milestone compaction (every 3 iterations):
  1. Review LEARNINGS.md
  2. Patterns confirmed 2+ times > graduate to CLAUDE.md anti-patterns
  3. Universal patterns (not project-specific) > also add to ~/.claude/CLAUDE.md
  4. Clear graduated entries from LEARNINGS.md
