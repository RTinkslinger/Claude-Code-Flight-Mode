# Flight Mode Plugin — V2 System Plan

**Date:** 2026-03-09
**Revision:** V2 (revised from V1 system plan after critical review)
**Purpose:** Make Claude Code resilient and efficient on unreliable in-flight WiFi — in ANY repository
**Target:** Claude Code plugin with `/flight-on` and `/flight-off` skills, hooks for automated safety nets
**Scope:** Generic, publishable plugin — not tied to any specific project or codebase

---

## Changes from V1

| Issue | V1 | V2 |
|---|---|---|
| Architecture | Loose markdown files + bash install script | Claude Code **plugin** (plugin.json, hooks, skills) |
| Installation | Per-repo copy + CLAUDE.md snippet paste | Global plugin install + 3-line CLAUDE.md snippet |
| Checkpoint overhead | Write `.flight-state.md` after EVERY micro-task (doubles API calls) | Rating-calibrated intervals + **Stop hook** as safety net |
| Context budget | Message-count heuristic (crude) | **PostToolUse hook** tracking tool calls + file read volume |
| Git commits | `git add -A` after every task | Specific file staging, frequency calibrated by rating, pre-commit hook aware |
| Commit squash | Interactive rebase (impossible in Claude Code) | Non-interactive `git reset --soft` approach |
| Profile format | 389-line prose file read in full | Compact lookup table at top + detailed reference below |
| Protocol location | Self-contained in FLIGHT_MODE.md OR verbose CLAUDE.md | **Layered**: full protocol in skill prompt, condensed in FLIGHT_MODE.md, hooks enforce |

---

## Core Insight (unchanged)

The problem isn't bandwidth — it's **unpredictable drops + context waste**. In-flight WiFi typically gives 4-15 Mbps down with 500-900ms latency, fine for Claude Code's tiny API payloads (~200 kbps). The real risks are:

1. **Mid-loop drops** — Claude is 8 steps into a 15-step plan, WiFi dies, context wasted
2. **Context bloat** — Claude reads 6 files "just in case", burns 40% context before real work
3. **No recovery path** — session dies, next session starts from zero

---

## Plugin Structure

```
flight-mode/
├── .claude-plugin/
│   └── plugin.json                  # Plugin manifest
├── skills/
│   └── flight-on/
│       └── SKILL.md                 # /flight-on activation skill
│   └── flight-off/
│       └── SKILL.md                 # /flight-off deactivation skill
├── hooks/
│   └── hooks.json                   # Hook configuration (Stop + PostToolUse)
├── scripts/
│   ├── stop-checkpoint.sh           # Auto-commit on session end
│   └── context-monitor.sh           # Track context usage, inject warnings
├── data/
│   └── flight-profiles.md           # Airline WiFi lookup table + reference
├── templates/
│   └── claude-md-snippet.md         # 3-line CLAUDE.md addition for users
├── README.md                        # Installation + usage
├── LICENSE                          # MIT
└── docs/
    ├── system-plan-v2.md            # This file
    └── start point - from cowork/   # Original research materials
```

**Runtime files (created in target repos at activation):**
- `FLIGHT_MODE.md` — exists = flight mode ON; contains airline, rating, condensed protocol
- `.flight-state.md` — checkpoint file (task state, progress, recovery instructions)

---

## Layered Protocol Architecture (Option C)

The behavioral protocol is split across four layers, each with a distinct responsibility:

| Layer | Contains | When Active | Context Cost |
|---|---|---|---|
| **Skill prompt** (`/flight-on`) | Full verbose protocol — atomization, checkpoint format, git discipline, context rules | One-time injection at activation | ~100 lines, one-time |
| **FLIGHT_MODE.md** (generated in repo) | Airline, rating, stable window + condensed protocol (~15-20 lines) | Read on session start / recovery | ~20 lines per session |
| **CLAUDE.md snippet** | 3 lines: "If FLIGHT_MODE.md exists, read it. If .flight-state.md has incomplete tasks, resume." | Always loaded | ~3 lines |
| **Hooks** | Context monitoring (PostToolUse), auto-checkpoint (Stop) | Fire automatically when FLIGHT_MODE.md exists | Zero context unless threshold hit |

**Why this works:**
- The skill prompt delivers the full protocol at activation (when you need it)
- FLIGHT_MODE.md has enough protocol for a recovering session to know the rules
- Hooks enforce context budget and auto-checkpoint mechanically — no self-policing needed
- The CLAUDE.md snippet is trivial to install (3 lines)
- Even without the snippet, hooks still fire (graceful degradation)

---

## Behavioral Protocol

### 1. Task Atomization

Before ANY work, decompose into micro-tasks. A micro-task is 1-2 tool calls maximum.

```
WRONG (normal mode):
"Let me refactor the auth module. I'll read 4 files, update middleware,
 fix tests, update docs, and run the test suite."

RIGHT (flight mode):
"Micro-task 1: Read src/auth/middleware.ts, understand structure"
"Micro-task 2: Edit token validation logic in lines 45-60"
→ checkpoint + git commit
"Micro-task 3: Read tests/auth.test.ts"
"Micro-task 4: Update test assertions"
→ checkpoint + git commit
```

**Rules:**
- Decompose into numbered micro-tasks BEFORE starting
- Write task list to `.flight-state.md`
- If user gives a big request, ASK to confirm decomposition first
- Micro-task granularity adapts by WiFi rating

### 2. Checkpoint Protocol (Revised)

**Key change from V1:** Checkpoints happen at rating-calibrated intervals, NOT after every micro-task. The Stop hook catches anything missed.

| Rating | Checkpoint `.flight-state.md` | Git commit |
|---|---|---|
| EXCELLENT | Every 4-5 micro-tasks | Every 4-5 tasks |
| GOOD | Every 3-4 | Every 3-4 |
| USABLE | Every 2-3 | Every 2-3 |
| CHOPPY | Every 1-2 | Every 1-2 |
| POOR | After every task | After every task |

**Checkpoint and commit happen together** — one `.flight-state.md` update + one git commit = 2 tool calls, amortized over multiple micro-tasks.

**`.flight-state.md` format:**
```markdown
# Flight State
**Session started:** 2026-03-09 14:30 UTC
**Airline:** [carrier] [route]
**WiFi rating:** [RATING]
**Project:** [repo name]

## Current Task
[User's request in plain language]

## Micro-Tasks
- [x] 1. [description] — [outcome]
- [x] 2. [description] — [outcome, commit hash]
- [ ] 3. [description]
- [ ] 4. [description]

## Last Action
[What just happened — 2-3 lines]

## Files Modified
- [file path] ([what changed])

## Recovery Instructions
If this session dropped: [Exact instructions for next session.
Which micro-task to start at. What state the code is in.]
```

### 3. Context Budget (Hook-Enforced)

The `context-monitor.sh` PostToolUse hook tracks:
- `tool_call_count` — incremented per tool call
- `file_reads` — count of Read/Grep/Glob calls
- `estimated_lines_read` — approximate lines consumed (from file sizes)

**Warning thresholds (injected into Claude's context by hook):**

| Estimated Usage | Hook Output | Claude Behavior |
|---|---|---|
| 0-40% | Silent (no output) | Normal micro-task execution |
| 40-60% | "~50% context. Consider checkpointing." | Checkpoint soon |
| 60-80% | "~70% context. Checkpoint NOW. Max 3 tasks." | Aggressive compaction |
| 80%+ | "~85% context. STOP. Checkpoint and suggest new session." | Stop work |

**Calculation:** `(tool_calls * 2.5 + lines_read * 0.01) / threshold * 100`

The hook is **silent below 40%** — zero overhead to Claude's context for the first half of a session.

### 4. Network Drop Handling

**Assume every API call might be the last.**

- Never start a file edit without the complete edit planned
- After successful edit: commit if it's a checkpoint interval
- Multi-file changes: file A → commit → file B → commit (never leave inconsistent state)
- Git commits use `flight:` prefix: `git commit -m "flight: [description]"`

**Stop hook safety net:** If Claude's session ends (graceful exit, error, user cancel), the stop hook:
1. Checks if `FLIGHT_MODE.md` exists
2. If uncommitted changes exist: stages modified files + commits with `flight: auto-checkpoint`
3. This catches drops where Claude didn't get to checkpoint

**Recovery from a drop:**
1. New session starts
2. Claude's CLAUDE.md snippet says "read FLIGHT_MODE.md if it exists"
3. Claude reads FLIGHT_MODE.md → gets rating + condensed protocol
4. Claude reads .flight-state.md → knows exactly where to resume
5. Claude resumes from next incomplete micro-task

### 5. Git Discipline

```bash
# Commit pattern — specific files, not git add -A
git add src/auth/middleware.ts tests/auth.test.ts
git commit -m "flight: completed micro-task 2 — updated token validation"

# Frequency calibrated by WiFi rating (see checkpoint table above)

# All flight commits use "flight:" prefix for easy identification
# Post-flight squash via /flight-off (non-interactive)
```

**Pre-commit hook handling:**
- Stage specific files (not `git add -A`)
- If pre-commit hook fails: note in `.flight-state.md`, skip commit, continue working
- Don't burn context debugging hook failures during flight mode
- Post-flight: user can address hook issues on stable ground

**Post-flight squash (non-interactive):**
```bash
# Find the commit before first flight: commit
BEFORE_FLIGHT=$(git log --oneline | grep -v "^.*flight:" | head -1 | cut -d' ' -f1)
# Squash all flight commits into one
git reset --soft $BEFORE_FLIGHT
git commit -m "feat: [summary of all flight work]"
```

---

## Slash Command Designs

### `/flight-on` (Skill)

**File: `skills/flight-on/SKILL.md`**

Activates flight mode for this session and project.

Flow:
1. Ask: airline + route, flight duration
2. Read `${CLAUDE_PLUGIN_ROOT}/data/flight-profiles.md` — find carrier in compact table
3. If not found: default to USABLE
4. Create `FLIGHT_MODE.md` in repo root with:
   - Airline, route, flight duration
   - WiFi rating + stable window
   - Activation timestamp
   - Condensed behavioral protocol (~15-20 lines)
5. Create `.flight-state.md` (or read existing if resuming)
6. Check `.gitignore` for runtime files — suggest adding if missing
7. Confirm: show rating, expected connectivity, behavior adaptations
8. Ask: "What do you want to work on?"
9. Decompose into micro-tasks, write to `.flight-state.md`
10. Confirm plan, begin micro-task 1

### `/flight-off` (Skill)

**File: `skills/flight-off/SKILL.md`**

Deactivates flight mode.

Flow:
1. Read `.flight-state.md` for final status
2. Summarize: tasks completed vs planned, files modified, flight commits count
3. Offer to squash `flight:` commits (non-interactive `git reset --soft`)
4. Delete `FLIGHT_MODE.md`
5. Archive `.flight-state.md` → `.flight-state-YYYY-MM-DD.md`
6. Confirm: "Flight mode off. Back to normal."
7. If incomplete tasks: note clearly for normal-session pickup

---

## Hook Designs

### hooks/hooks.json

```json
{
  "description": "Flight mode hooks — auto-checkpoint on session end, context monitoring",
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/stop-checkpoint.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Read|Edit|Write|Bash|Grep|Glob",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/context-monitor.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### scripts/stop-checkpoint.sh

```bash
#!/bin/bash
set -euo pipefail

# Only act if flight mode is active
[ -f "FLIGHT_MODE.md" ] || exit 0

# Check for uncommitted changes
if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
  exit 0
fi

# Stage modified tracked files (not untracked — respect .gitignore)
git add -u 2>/dev/null || true

# Commit with auto-checkpoint message
git commit -m "flight: auto-checkpoint on session end" --no-verify 2>/dev/null || true

echo '{"systemMessage": "Flight mode: auto-checkpointed uncommitted changes."}'
exit 0
```

### scripts/context-monitor.sh

```bash
#!/bin/bash
set -euo pipefail

# Only act if flight mode is active
[ -f "FLIGHT_MODE.md" ] || exit 0

# State file in /tmp keyed by project directory
STATE_DIR="/tmp/flight-mode-$(echo "$PWD" | md5sum 2>/dev/null | cut -c1-12 || md5 -q -s "$PWD" | cut -c1-12)"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/context.json"

# Read input
input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // ""')

# Initialize or read state
if [ -f "$STATE_FILE" ]; then
  tool_calls=$(jq -r '.tool_calls' "$STATE_FILE")
  file_reads=$(jq -r '.file_reads' "$STATE_FILE")
  lines_read=$(jq -r '.lines_read' "$STATE_FILE")
else
  tool_calls=0
  file_reads=0
  lines_read=0
fi

# Update counters
tool_calls=$((tool_calls + 1))

if [[ "$tool_name" == "Read" || "$tool_name" == "Grep" || "$tool_name" == "Glob" ]]; then
  file_reads=$((file_reads + 1))
  # Estimate lines from tool output length (rough proxy)
  output_len=$(echo "$input" | jq -r '.tool_output // ""' | wc -l 2>/dev/null || echo "0")
  lines_read=$((lines_read + output_len))
fi

# Save state
cat > "$STATE_FILE" << EOF
{"tool_calls": $tool_calls, "file_reads": $file_reads, "lines_read": $lines_read}
EOF

# Calculate estimated usage
estimated=$(echo "$tool_calls $lines_read" | awk '{printf "%.0f", ($1 * 2.5 + $2 * 0.01) / 1.5}')

# Inject warnings at thresholds
if [ "$estimated" -ge 85 ]; then
  echo "{\"systemMessage\": \"FLIGHT MODE: ~${estimated}% context estimated. STOP. Write recovery instructions to .flight-state.md and suggest starting a new session.\"}"
elif [ "$estimated" -ge 65 ]; then
  echo "{\"systemMessage\": \"FLIGHT MODE: ~${estimated}% context estimated. Checkpoint NOW. Max 3 more micro-tasks remaining.\"}"
elif [ "$estimated" -ge 45 ]; then
  echo "{\"systemMessage\": \"FLIGHT MODE: ~${estimated}% context estimated. Consider checkpointing soon.\"}"
fi
# Below 45%: silent — zero context overhead

exit 0
```

---

## WiFi Profiles (Revised Format)

The `data/flight-profiles.md` file is restructured with a **compact lookup table** at the top that Claude reads first:

```markdown
# Flight Mode — Airline WiFi Profiles

## Quick Lookup Table

| Carrier | Rating (domestic) | Rating (long-haul) | Stable Window | Key Note |
|---|---|---|---|---|
| Delta | GOOD | USABLE | 45-90 / 20-40 min | Upload <1 Mbps |
| United (Starlink) | EXCELLENT | USABLE | 60+ / 20-40 min | Check aircraft type |
| United (legacy) | USABLE | USABLE | 20-40 min | GEO fleet |
| American (narrow) | USABLE | — | 15-30 min | Re-auth after sleep |
| American (wide) | CHOPPY | CHOPPY | 15-30 min | Panasonic hardware |
| JetBlue | GOOD | — | 30-60 min | Free for all |
| Southwest (current) | CHOPPY | — | 10-20 min | Starlink rollout mid-2026 |
| Alaska (legacy) | CHOPPY | — | 15-30 min | Starlink rollout underway |
| Air Canada | GOOD | USABLE | 30-60 min | Free for Aeroplan |
| Air France | EXCELLENT | EXCELLENT | 60+ min | Starlink fleet |
| KLM | GOOD | — | 30-60 min | European routes |
| Lufthansa (legacy) | CHOPPY | CHOPPY | 10-20 min | Hardware lottery |
| Lufthansa (Starlink) | EXCELLENT | EXCELLENT | 60+ min | Limited fleet |
| Etihad (new) | GOOD | GOOD | 30-45 min | Amara aircraft |
| Emirates | USABLE | USABLE | 20-40 min | Premium tier needed |
| Qatar | USABLE | USABLE | 20-40 min | Varies by aircraft |
| Cathay Pacific | USABLE | USABLE | 20-40 min | Standard satellite |
| Singapore Airlines | USABLE | USABLE | 20-40 min | Workable |
| ANA (767 Viasat) | GOOD | — | 30-60 min | Free all classes |
| ANA (777 long-haul) | CHOPPY | CHOPPY | 10-20 min | Hour-long blackouts |
| Thai (NSG) | GOOD | GOOD | 30-60 min | Multi-orbit |
| Air India | USABLE | USABLE | 20-40 min | Portal login finicky |
| Ryanair/easyJet/Wizz | POOR | — | — | No viable WiFi |
| Asian LCCs | POOR | POOR | — | Not reliable |
| UNKNOWN/Default | USABLE | USABLE | 20-30 min | Standard protocol |

## Route Patterns (cross-carrier)
| Route Type | Typical Rating | Notes |
|---|---|---|
| US Domestic | GOOD-EXCELLENT | Best corridor |
| Transatlantic | GOOD-EXCELLENT | Dense satellite coverage |
| Transpacific | USABLE | Handoff drops, 1-3 per crossing |
| Europe-Asia | USABLE-CHOPPY | Equatorial risk |
| Polar routes | CHOPPY-POOR | Arctic blackout windows |
| Equatorial | CHOPPY-POOR | Worst for satellite physics |

## Detailed Carrier Profiles
[Full prose profiles below, only read if user asks for details...]
```

---

## CLAUDE.md Snippet

Users add this to `~/.claude/CLAUDE.md` (one-time, 3 lines):

```markdown
## Flight Mode
If `FLIGHT_MODE.md` exists in this repo root, read it before doing anything else.
If `.flight-state.md` exists with incomplete tasks, resume from the last checkpoint.
```

---

## Implementation Phases

### Phase 1: Plugin Foundation + Core Flight Mode

**Goal:** Installable plugin with working `/flight-on` and `/flight-off`.

| Step | Deliverable | Details |
|---|---|---|
| 1 | Plugin scaffold | `.claude-plugin/plugin.json`, directory structure |
| 2 | `/flight-on` skill | `skills/flight-on/SKILL.md` with full protocol |
| 3 | `/flight-off` skill | `skills/flight-off/SKILL.md` with summary + squash |
| 4 | Flight profiles | `data/flight-profiles.md` — compact table + full reference |
| 5 | FLIGHT_MODE.md template | Template content for the generated file |
| 6 | CLAUDE.md snippet | `templates/claude-md-snippet.md` |
| 7 | .gitignore template | Runtime files to ignore |

### Phase 2: Hooks + Automated Safety Nets

**Goal:** Mechanical enforcement of context budget and checkpointing.

| Step | Deliverable | Details |
|---|---|---|
| 8 | hooks.json | Hook configuration (Stop + PostToolUse) |
| 9 | stop-checkpoint.sh | Auto-commit on session end |
| 10 | context-monitor.sh | Track usage, inject warnings at thresholds |
| 11 | Testing | Test hooks with `claude --debug --plugin-dir .` |

### Phase 3: Polish + Publish

**Goal:** Ready for any Claude Code user to install from GitHub.

| Step | Deliverable | Details |
|---|---|---|
| 12 | README.md | Installation, usage, post-flight cleanup |
| 13 | LICENSE | MIT |
| 14 | End-to-end testing | Full flow: activate → work → kill → recover → deactivate |
| 15 | Publish | Push to GitHub, tag v1.0.0 |

---

## Out of Scope (V1)

- Auto-detection of bad WiFi (latency-based activation)
- Offline mode (this is degraded-network, not offline)
- Auto-updating profiles
- Train/hotel/conference mode variants
- Background execution
- Non-git repos (git is required)

---

## Future Enhancements (Post-V1)

- Auto-detect flight mode via latency measurement
- WiFi health indicator at session start
- SessionStart hook to auto-detect FLIGHT_MODE.md (remove need for CLAUDE.md snippet)
- Post-flight digest for Slack/meeting notes
- Profile auto-update via research agents
- Train/hotel mode variants
