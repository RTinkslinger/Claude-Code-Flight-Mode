# Flight Mode for Claude Code — V1 System Plan

**Date:** 2026-03-09
**Purpose:** Make Claude Code resilient and efficient on unreliable in-flight WiFi — in ANY repository
**Target:** Standalone project with custom slash commands `/flight-on` and `/flight-off` that work across all repos
**Scope:** Generic Claude Code behavioral override — not tied to any specific project or codebase

---

## Core Insight

The problem isn't bandwidth — it's **unpredictable drops + context waste**. In-flight WiFi (satellite-based) typically gives 4-15 Mbps down with 500-900ms latency, which is fine for Claude Code's tiny API payloads (~200 kbps). The real risks are:

1. **Mid-loop drops** — Claude is 8 steps into a 15-step plan, WiFi dies, context is wasted
2. **Context bloat** — Claude reads 6 files "just in case", burns 40% context before doing real work
3. **No recovery path** — session dies, next session starts from zero with no memory of what happened

Flight mode solves all three by changing **how Claude thinks**, not what model it uses. It's degraded-network mode, not offline mode. Claude Opus remains the model — we just change the interaction pattern.

---

## Project Structure

This is a **standalone project** — not embedded inside any specific repo. It produces files that get installed into any repo's `.claude/` directory.

```
claude-flight-mode/
├── README.md                     # Setup instructions
├── install.sh                    # Script to install flight mode into any repo
├── commands/
│   ├── flight-on.md              # Slash command: activates flight mode
│   └── flight-off.md             # Slash command: deactivates flight mode
├── flight-profiles.md            # Airline WiFi characteristics (Cowork-researched)
├── claude-md-snippet.md          # CLAUDE.md block to paste into any project
└── docs/
    └── system-plan.md            # This file
```

**Installation into any repo:**
```bash
# From the target repo root:
cp -r /path/to/claude-flight-mode/commands/* .claude/commands/
cp /path/to/claude-flight-mode/flight-profiles.md .claude/flight-profiles.md
# Then paste the CLAUDE.md snippet into your project's CLAUDE.md
```

Or via `install.sh` which automates the above + appends the CLAUDE.md snippet.

**Runtime files (created in the target repo at activation):**
```
<any-repo>/
├── FLIGHT_MODE.md            # Exists = flight mode is ON (persistent toggle)
└── .flight-state.md          # Runtime checkpoint file (task state, progress)
```

---

## WiFi Profiles (`flight-profiles.md`)

Claude reads this when flight mode activates to calibrate expectations — drop frequency, latency, and stable window duration.

> **Build Note:** The WiFi profiles reference file is built and maintained via **Cowork deep research** (parallel agents researching carrier + route WiFi characteristics across 40+ airlines). Cowork generates the comprehensive `flight-profiles.md` and saves it to this project. Claude Code consumes this as a **read-only reference** — it does NOT maintain or update the profiles itself. When new carriers/routes are needed, trigger a Cowork research session to regenerate the file. This is a designed plug point: Cowork handles the research-heavy, network-dependent work; Claude Code handles the offline-resilient execution.

The profile file follows this schema per carrier:

```markdown
### [Carrier Name] ([Technology Provider] — [Satellite System])
- **Routes:** Key routes with WiFi coverage
- **Download:** X-Y Mbps (shared across cabin)
- **Upload:** X-Y Mbps
- **Latency:** X-Y ms baseline
- **Drop pattern:** Frequency, duration, known dead zones
- **Fleet coverage:** Which aircraft types have WiFi
- **Pricing:** Free / paid / tiered
- **Rating:** EXCELLENT / GOOD / USABLE / CHOPPY / POOR
- **Stable window:** Expected uninterrupted stretch (e.g., 30-60 min)
- **Dev notes:** Specific guidance for API-dependent workflows
```

**Rating scale (used by flight mode to calibrate behavior):**

| Rating | Meaning | Micro-task batch size | Commit frequency |
|---|---|---|---|
| EXCELLENT | Starlink-equipped, near-ground connectivity | Up to 5 micro-tasks queued | Every 4-5 tasks |
| GOOD | Stable satellite, long uninterrupted windows | Up to 3 micro-tasks queued | Every 3-4 tasks |
| USABLE | Standard satellite, periodic drops | 1-2 micro-tasks at a time | Every 2-3 tasks |
| CHOPPY | Frequent micro-drops, unreliable | 1 micro-task at a time | After every task |
| POOR | Barely functional, long outages | 1 micro-task, minimal file reads | After every task |
| UNKNOWN | Carrier/route not in profiles | Defaults to USABLE behavior | Every 2-3 tasks |

---

## Behavioral Protocol (The Core)

When `FLIGHT_MODE.md` exists in a repo, Claude Code follows these rules. This is what makes flight mode work — it's prompt engineering, not infrastructure.

### 1. Task Atomization Protocol

**Before ANY work, decompose into micro-tasks.**

A micro-task is: 1-2 tool calls maximum. Read one file, make one edit. Run one command, check output. Never plan a chain of 5+ operations.

```
WRONG (normal mode):
"Let me refactor the auth module. I'll read 4 files, update the middleware,
 fix the tests, update the docs, and run the test suite."

RIGHT (flight mode):
"Micro-task 1: Read src/auth/middleware.ts, understand current structure"
→ checkpoint
"Micro-task 2: Edit the token validation logic in lines 45-60"
→ checkpoint + git commit
"Micro-task 3: Read tests/auth.test.ts"
→ checkpoint
"Micro-task 4: Update test assertions for new validation"
→ checkpoint + git commit
```

**Rules:**
- Decompose the user's request into numbered micro-tasks BEFORE starting
- Write the task list to `.flight-state.md`
- Execute ONE micro-task, then update `.flight-state.md`
- Git commit frequency is calibrated by WiFi rating (see table above)
- If user gives a big request, ASK to confirm the decomposition before starting
- Micro-task granularity adapts: EXCELLENT rating allows slightly larger tasks; POOR rating means truly atomic (one edit, one commit)

### 2. Checkpoint Protocol

**`.flight-state.md` is the flight recorder.** Updated after every micro-task.

```markdown
# Flight State
**Session started:** 2026-03-09 14:30 UTC
**Airline:** [carrier] [route]
**WiFi rating:** [RATING] (expect drops every ~[N] min)
**Project:** [repo name / path]

## Current Task
[User's request in plain language]

## Micro-Tasks
- [x] 1. [description] — [outcome summary]
- [x] 2. [description] — [outcome summary, commit hash]
- [ ] 3. [description]
- [ ] 4. [description]

## Last Action
[What just happened — 2-3 lines max]

## Files Modified This Session
- [file path] ([what changed])

## Recovery Instructions
If this session dropped: [Exact instructions for the next session to resume.
Which micro-task to start at. What state the code is in. Any uncommitted work.]
```

**Why this works:** If WiFi drops and the session dies, the next session reads `.flight-state.md` first and picks up exactly where it left off. Zero context wasted on re-discovery.

**Checkpoint discipline:**
- BEFORE a tool call: write what you're about to do to "Last Action"
- AFTER a tool call: write what happened, update task list
- The "Recovery Instructions" field is the critical one — write it as if a different Claude session will read it cold

### 3. Context Budget Management

Claude Code doesn't expose context % directly, but we can use a **message-count heuristic** as a proxy. These thresholds apply regardless of which model is being used:

| Proxy Signal | Estimated Context | Behavior |
|---|---|---|
| < 15 exchanges | 0-30% | Normal micro-task execution |
| 15-30 exchanges | 30-50% | Start compacting — summarize before continuing |
| 30-40 exchanges | 50-70% | Max 3 pending micro-tasks. Aggressive compaction. |
| 40+ exchanges | 70%+ | STOP. Checkpoint everything. Suggest new session. |

**Context frugality rules:**
- Never read a file "just to understand the codebase" — only read what the current micro-task needs
- Don't re-read project config files (CLAUDE.md, README, etc.) mid-session unless specifically needed
- When summarizing progress, be terse (3-5 lines, not paragraphs)
- Prefer `grep` / `rg` for targeted lookups over full file reads
- If a file was already read this session, reference from memory — don't re-read
- Avoid multi-file diffs or large code reviews — break them into per-file micro-tasks

**At 50%+ context, the throttle kicks in:**
- Do NOT accept new user requests that would add more than 3 micro-tasks
- Suggest: "We're at ~50% context. I can do [2-3 specific things] or we should start a fresh session. I've checkpointed everything to .flight-state.md."
- At 70%+, actively push for a new session — the checkpoint file means this is cheap

### 4. Network Drop Handling

**Assume every API call might be the last.**

- Never start a file edit without having the complete edit planned (no "let me read line by line and decide as I go")
- After any successful edit: immediately commit if it's a logical unit
- If a multi-file change is needed: do file A → commit → do file B → commit. Never leave two files in an inconsistent state
- Git commits in flight mode are frequent and small: `git commit -m "flight: [micro-task description]"`

**Recovery from a drop:**
1. New session starts
2. Claude reads `FLIGHT_MODE.md` (knows flight mode is active, reads WiFi profile)
3. Claude reads `.flight-state.md` (knows exactly where things stand)
4. Claude resumes from the next incomplete micro-task
5. No context is wasted re-establishing state

**For non-git projects:** If the repo doesn't use git, the checkpoint file is the only safety net. Claude should still write `.flight-state.md` after every action, but cannot rely on commits for rollback.

### 5. Git Discipline in Flight Mode

```bash
# Flight mode commit pattern
git add -A && git commit -m "flight: completed micro-task N — [description]"

# Frequency calibrated by WiFi rating
# EXCELLENT/GOOD: every 3-4 micro-tasks
# USABLE: every 2-3 micro-tasks
# CHOPPY/POOR: after every micro-task

# All flight commits use the "flight:" prefix for easy identification
# Can be squashed post-flight: git rebase -i
```

Post-flight cleanup: User can squash all `flight:` prefixed commits into logical units. The `/flight-off` command offers to do this.

---

## Slash Command Designs

### `/flight-on`

**File: `.claude/commands/flight-on.md`**

```markdown
Activate flight mode for this session and project.

Ask me:
1. Which airline and route? (e.g., "Cathay Pacific HKG-LHR", "Delta JFK-LAX", "United SFO-NRT")
2. Roughly how long is the flight?

Then:
1. Read `.claude/flight-profiles.md` and look up the carrier
2. If carrier not found, use the UNKNOWN/fallback profile
3. Create `FLIGHT_MODE.md` in the project root with:
   - Airline, route, and flight duration
   - WiFi rating and profile summary
   - Expected drop pattern and stable window
   - Activation timestamp
   - Behavioral rules summary (from the flight mode protocol)
4. Create `.flight-state.md` with empty task list (or read existing one if resuming)
5. Confirm activation: show the WiFi rating, expected connectivity, and how behavior will adapt
6. Ask: "What do you want to work on during this flight?"

After I tell you the task:
- Decompose into numbered micro-tasks
- Write them to `.flight-state.md`
- Show me the plan and confirm before starting
- Begin executing micro-task 1

IMPORTANT: From this point forward, follow the flight mode behavioral protocol.
Key rules:
- Atomic micro-tasks (1-2 tool calls each)
- Update `.flight-state.md` after every micro-task
- Git commit frequency based on WiFi rating
- Context frugality — only read files the current micro-task needs
- At 50%+ context, throttle to max 3 pending tasks
- At 70%+ context, checkpoint and suggest new session
- Every edit should be self-contained — assume WiFi could drop after any action
- Recovery instructions in `.flight-state.md` should be written as if a different session will read them cold
```

### `/flight-off`

**File: `.claude/commands/flight-off.md`**

```markdown
Deactivate flight mode for this project.

1. Read `.flight-state.md` for final status
2. Summarize what was accomplished during the flight:
   - Total micro-tasks completed vs planned
   - Files modified (list them)
   - Git commits made (count + list flight: prefixed ones)
   - Any tasks remaining / incomplete
3. Ask: "Want me to squash the flight commits into logical units?"
   - If yes: identify logical groupings and run interactive rebase
   - If no: leave commits as-is
4. Delete `FLIGHT_MODE.md` from project root
5. Rename `.flight-state.md` to `.flight-state-[YYYY-MM-DD].md` (archive, don't delete)
6. Confirm: "Flight mode off. Back to normal operations."

If there are incomplete tasks, note them clearly so I can pick them up in a normal session.
```

---

## CLAUDE.md Snippet

Add this block to any project's CLAUDE.md to enable flight mode detection:

```markdown
## Flight Mode (Conditional)

If `FLIGHT_MODE.md` exists in this repository root, flight mode is ACTIVE.
On session start, read `FLIGHT_MODE.md` for airline/route/WiFi context and
`.flight-state.md` for current task state before doing anything else.

When flight mode is active:
- Decompose all work into micro-tasks (1-2 tool calls each)
- Update `.flight-state.md` after every micro-task with completion status + recovery instructions
- Git commit frequency calibrated by WiFi rating in FLIGHT_MODE.md
- Never read files speculatively — only what the current micro-task needs
- At ~50% context (30+ exchanges), throttle to max 3 pending tasks
- At ~70% context (40+ exchanges), checkpoint everything and suggest new session
- Every edit should be self-contained — assume WiFi could drop after any action
- On session start: if `.flight-state.md` has incomplete tasks, resume from last checkpoint
- Write recovery instructions as if a completely fresh session will read them
```

---

## What This Doesn't Solve (V1 Scope)

1. **Auto-retry on network drops** — Claude Code's CLI handles TCP retry already. If the connection drops mid-stream, the CLI shows an error and you re-run. The checkpoint file means you don't lose progress.

2. **Actual context % API** — Anthropic doesn't expose this. The message-count heuristic is a reasonable proxy. If Anthropic adds a context usage header in the future, this can be upgraded.

3. **Background execution** — Claude Code is single-session. We don't try to fake background runners. The micro-task + checkpoint pattern achieves the same resilience without complexity.

4. **Offline mode** — This is explicitly NOT offline mode. It's degraded-network mode. If you need true offline coding, that's a different solution (local models via Ollama/Cursor).

5. **Auto-detection** — V1 requires manual activation via `/flight-on`. Auto-detection based on latency measurement is a V2 enhancement.

---

## Installation & Setup

### Quick Install (per repo)
```bash
# Clone or download the flight mode project
git clone <flight-mode-repo> ~/claude-flight-mode

# Install into any project
cd /path/to/your/project
~/claude-flight-mode/install.sh

# Or manual:
mkdir -p .claude/commands
cp ~/claude-flight-mode/commands/flight-on.md .claude/commands/
cp ~/claude-flight-mode/commands/flight-off.md .claude/commands/
cp ~/claude-flight-mode/flight-profiles.md .claude/
# Then paste claude-md-snippet.md content into your CLAUDE.md
```

### Global Install (all repos)
For the CLAUDE.md snippet, add it to `~/.claude/CLAUDE.md` (global Claude Code config) instead of per-project. The slash commands still need to be per-project (Claude Code limitation), but the behavioral protocol will apply everywhere.

### .gitignore
Add these to your project's `.gitignore`:
```
FLIGHT_MODE.md
.flight-state.md
.flight-state-*.md
```
These are runtime/personal files — don't commit them to shared repos.

---

## Implementation Checklist

- [ ] Create project directory `claude-flight-mode/`
- [ ] Create `commands/flight-on.md` with activation prompt
- [ ] Create `commands/flight-off.md` with deactivation prompt
- [ ] Create `flight-profiles.md` with researched airline WiFi data (from Cowork deep research)
- [ ] Create `claude-md-snippet.md` with the CLAUDE.md block
- [ ] Create `install.sh` to automate per-repo installation
- [ ] Create `README.md` with usage instructions
- [ ] Test in a sample repo: activate → do 3-4 micro-tasks → kill terminal → new session → verify resume
- [ ] Test context throttling behavior at 30+ exchanges
- [ ] Test with unknown carrier (fallback profile)
- [ ] Install into primary working repos

**Estimated build time:** 1-2 hours in Claude Code. The commands are markdown files. The behavioral change is prompt engineering. The checkpoint protocol is markdown file writes. `install.sh` is a ~20 line bash script.

---

## Future Enhancements (Post-V1)

- **Auto-detect flight mode:** If latency consistently >500ms for 3+ consecutive API calls, suggest activating flight mode
- **WiFi health indicator:** Ping-based check at session start, dynamically adjusts micro-task batch size
- **Global flight state:** `~/.claude/flight-mode` that applies to ALL repos without per-repo FLIGHT_MODE.md
- **Post-flight digest:** Auto-generate a summary of everything accomplished, suitable for pasting into a meeting note or Slack
- **Latency-adaptive batching:** Measure actual round-trip time per API call, dynamically adjust micro-task granularity
- **Profile auto-update:** Periodic Cowork research sessions to refresh airline WiFi data as fleets upgrade (Starlink rollouts, etc.)
- **Train/hotel mode:** Same degraded-network protocol adapted for other unreliable connectivity scenarios (trains, hotels, conferences)
- **Flight calendar integration:** Read upcoming flights from Google Calendar, pre-suggest flight mode activation with the right carrier/route
