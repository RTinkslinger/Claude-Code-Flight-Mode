---
name: flight-on
description: Activate flight mode for resilient coding on unreliable in-flight WiFi. Use when the user is about to work on a flight or mentions airplane WiFi.
argument-hint: [airline route]
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Flight Mode — Activation Protocol

You are activating **flight mode** — a behavioral shift that makes you resilient on unreliable in-flight WiFi. This protocol changes HOW you think, plan, and execute. Every API call might be the last one that gets through.

## Step 1: Gather Flight Info

Ask the user (or parse from `$ARGUMENTS`):
- **Airline** (e.g., "Cathay Pacific", "Delta", "United")
- **Route** (e.g., "HKG-LAX", "JFK-LHR", "SFO-NRT")
- **What they want to work on** (can ask this now or after showing the rating)

If the user provided arguments like `/flight-on Delta JFK-LHR`, parse them directly.

## Step 2: Look Up WiFi Profile

Read the airline WiFi profiles:
```
${CLAUDE_PLUGIN_ROOT}/data/flight-profiles.md
```

**Read ONLY the Quick Lookup Table and Route Patterns sections** (stop before "Detailed Carrier Profiles"). Find the carrier in the table. If not found, use the UNKNOWN/Default row (USABLE rating).

Cross-reference with the Route Patterns table — if the route type suggests a worse rating than the carrier default, use the worse rating. For example: a GOOD carrier on a polar route might degrade to CHOPPY.

Determine:
- **WiFi Rating**: EXCELLENT, GOOD, USABLE, CHOPPY, POOR, or UNKNOWN
- **Stable Window**: expected minutes of continuous connectivity
- **Key Note**: any carrier-specific gotchas

## Step 3: Show Rating & Calibration

Tell the user what to expect:

```
Flight Mode: [Airline] [Route]
WiFi Rating: [RATING]
Stable Window: ~[X-Y] min between drops
[Key Note if relevant]

Calibration:
- Micro-task batch: [1-5 depending on rating]
- Checkpoint every: [1-5 tasks]
- Git commit every: [1-5 tasks]
```

Use this calibration table:

| Rating | Micro-task batch | Checkpoint interval | Commit interval |
|---|---|---|---|
| EXCELLENT | Up to 5 queued | Every 4-5 tasks | Every 4-5 tasks |
| GOOD | Up to 3 queued | Every 3-4 tasks | Every 3-4 tasks |
| USABLE | 1-2 at a time | Every 2-3 tasks | Every 2-3 tasks |
| CHOPPY | 1 at a time | Every 1-2 tasks | Every 1-2 tasks |
| POOR | 1, minimal reads | After every task | After every task |
| UNKNOWN | 1-2 at a time | Every 2-3 tasks | Every 2-3 tasks |

## Step 4: Create FLIGHT_MODE.md

Write `FLIGHT_MODE.md` in the repo root. This file's existence = flight mode is ON. Its content provides the condensed protocol for session recovery.

```markdown
# Flight Mode Active

**Airline:** [airline] [route]
**WiFi Rating:** [RATING] (drops expected every ~[X-Y] min)
**Activated:** [YYYY-MM-DD HH:MM]
**Stable Window:** [X-Y] min

## Condensed Protocol (for session recovery)

1. **Read `.flight-state.md`** — resume from last incomplete micro-task
2. **Micro-tasks only** — max [batch size] tool calls per task, decompose before starting
3. **Checkpoint every [N] tasks** — update `.flight-state.md` + git commit
4. **Git discipline** — `flight:` prefix, stage specific files (not `git add -A`), skip failed pre-commit hooks
5. **Context budget** — minimize file reads, read only what the current micro-task needs
6. **If a drop seems imminent** — finish current edit, commit immediately, update `.flight-state.md`
7. **Every edit must be self-contained** — never leave files in an inconsistent state
```

## Step 4b: Create Initial .flight-state.md

Create a minimal `.flight-state.md` immediately — this ensures recovery works even if the session is killed before task decomposition:

```markdown
# Flight State

**Session started:** [YYYY-MM-DD HH:MM]
**Airline:** [airline] [route]
**WiFi rating:** [RATING] (drops expected every ~[X-Y] min)
**Project:** [repo name or cwd basename]

## Current Task
(awaiting user input)

## Micro-Tasks
(not yet decomposed)

## Last Action
Flight mode activated. Awaiting task assignment.

## Files Modified This Session
(none yet)

## Recovery Instructions
If this session dropped: Flight mode is active but no task was assigned yet. Ask the user what they want to work on.
```

This file will be **replaced** with the full version in Step 7 once micro-tasks are defined.

## Step 5: Check .gitignore

Check if the repo has a `.gitignore`. If it exists, check whether `FLIGHT_MODE.md` and `.flight-state.md` are listed. If not, tell the user:

```
Note: FLIGHT_MODE.md and .flight-state.md are runtime files.
I recommend adding them to .gitignore:

  FLIGHT_MODE.md
  .flight-state.md
  .flight-state-*.md

Want me to add these? (y/n)
```

If the user agrees, append them. If the user declines or there's no `.gitignore`, proceed — these files are harmless if committed.

## Step 6: Get the Task

If the user hasn't already said what they want to work on, ask:

```
What do you want to work on this flight?
```

## Step 7: Decompose into Micro-Tasks

Break the user's request into numbered micro-tasks. Each micro-task should be:
- **1-2 tool calls maximum** (one read + one edit, or one edit + one commit)
- **Self-contained** — if the session drops after this task, the codebase is in a valid state
- **Ordered by dependency** — earlier tasks don't depend on later ones

**Replace** the initial `.flight-state.md` (created in Step 4b) with the full version:

```markdown
# Flight State

**Session started:** [YYYY-MM-DD HH:MM]
**Airline:** [airline] [route]
**WiFi rating:** [RATING] (drops expected every ~[X-Y] min)
**Project:** [repo name or description]

## Current Task
[User's request in plain language]

## Micro-Tasks
- [ ] 1. [description]
- [ ] 2. [description]
- [ ] 3. [description]
...

## Last Action
Session just started. Micro-task decomposition complete.

## Files Modified This Session
(none yet)

## Recovery Instructions
If this session dropped: Read this file, resume from the first unchecked micro-task. The codebase is in a clean state — no partial edits.
```

Show the plan to the user and confirm before starting:

```
Here's the plan ([N] micro-tasks, checkpointing every [M]):

1. [description]
2. [description]
...

Ready to start?
```

## Step 8: Begin Work

Once confirmed, start micro-task 1. Follow the behavioral rules below for every task.

---

# Behavioral Protocol (Active for Entire Session)

These rules remain in effect from activation until `/flight-off` or session end.

## Rule 1: Micro-Task Execution

- Execute ONE micro-task at a time (or up to batch size for EXCELLENT/GOOD)
- After completing a micro-task, mark it `[x]` in `.flight-state.md` with a brief outcome
- **Never start a multi-file change without the complete plan** — partial changes across files = danger zone
- If the task needs files you haven't read, that's a separate micro-task first

## Rule 2: Checkpoint Discipline

At the checkpoint interval for the current rating:

1. **Update `.flight-state.md`** — mark completed tasks, update "Last Action" and "Files Modified"
2. **Git commit** — stage specific files, use `flight:` prefix:
   ```
   git add [specific files]
   git commit -m "flight: [what was done]"
   ```
3. **Update Recovery Instructions** — if the session dropped right now, what should the next session know?

Checkpoint and commit happen **together** — one `.flight-state.md` update + one `git commit` = 2 tool calls.

## Rule 3: Git Discipline

- **Always use `flight:` prefix** in commit messages
- **Stage specific files** — never `git add -A` or `git add .`
- **If a pre-commit hook fails:** note it in `.flight-state.md`, skip the commit, continue working. Don't burn context debugging hook failures during flight mode. The user can fix them post-flight.
- **Multi-file atomic changes:** file A edit + commit, then file B edit + commit. Never leave inconsistent cross-file state.

## Rule 4: Context Budget

Be **miserly** with context consumption:

- **Don't read files speculatively** — only read what the current micro-task needs
- **Don't read entire large files** — use line ranges if you know where to look
- **Don't re-read files** you've already read this session unless they've been modified
- **Don't spawn subagents** unless absolutely necessary (each burns context)
- **Prefer Grep with targeted patterns** over reading whole files
- **One exploration task, then execute** — don't do multi-round exploration

If you feel the session is getting long or the context is heavy:
1. Checkpoint immediately
2. Write detailed recovery instructions to `.flight-state.md`
3. Tell the user: "Context is getting heavy. I recommend starting a new session — I've saved recovery state."

## Rule 5: Network Drop Handling

**Assume every API call might be the last.**

- Complete each edit fully before moving on — no "I'll fix that in the next step"
- After a successful edit: if it's a checkpoint interval, commit immediately
- If you sense instability (slow responses, errors): emergency checkpoint — commit what you have NOW
- Never leave the codebase in a broken state between tool calls

## Rule 6: Communication

- Keep status updates SHORT — the user is on a plane, they want progress not prose
- After each micro-task: one line status (e.g., "Task 3 done: updated auth middleware")
- At checkpoints: brief progress summary + committed hash
- If blocked: explain the blocker concisely, suggest workaround or defer to post-flight

## Rule 7: Recovery State

`.flight-state.md` must ALWAYS be current enough that a fresh session can pick up seamlessly:

- **Which micro-task to resume** — first unchecked item
- **What state the code is in** — which files were modified and what's left
- **Any decisions made** — so the next session doesn't re-derive them
- **Blockers or deferred items** — anything punted to post-flight

---

# Post-Flight Squash Reference

When the user runs `/flight-off`, flight commits will be squashed. The approach:

```bash
# Find the commit before first flight: commit
BEFORE_FLIGHT=$(git log --oneline | grep -v "^.*flight:" | head -1 | cut -d' ' -f1)
# Squash all flight commits into one
git reset --soft $BEFORE_FLIGHT
git commit -m "feat: [summary of all flight work]"
```

This is non-interactive and safe. The user decides whether to squash via `/flight-off`.
