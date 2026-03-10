---
name: flight-on
description: Activate flight mode for resilient coding on unreliable in-flight WiFi. Use when the user is about to work on a flight or mentions airplane WiFi.
argument-hint: [flight-code or airline route]
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Flight Mode — Activation

## Preflight Results

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/flight-on-preflight.sh" "$ARGUMENTS" "${CLAUDE_PLUGIN_ROOT}" 2>/dev/null || echo '{"error":"preflight failed","ready":false,"missing":["airline","route"]}'`

## What To Do With These Results

The JSON above was gathered automatically. Your job is to interpret it and fill gaps.

### Step 1: Check if ready

Read the `ready` field:
- If `true` → skip to Step 3 (Summary)
- If `false` → go to Step 2

### Step 2: Fill missing info

Read the `missing` array. Ask the user ONE question to fill the gaps:
- `["airline", "route"]` → "What flight are you on? (e.g., CX624 BLR-HKG)"
- `["route"]` → "What's the route? (e.g., BLR-HKG)"
- `["airline"]` → "What airline? (e.g., CX or Cathay Pacific)"

Once you have the answer, run the lookup script:
```bash
echo '{"airline_code":"CODE","origin":"XXX","destination":"YYY","plugin_dir":"${CLAUDE_PLUGIN_ROOT}","dashboard_dir":"SERVE_DIR"}' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/flight-on-lookup.sh"
```
Replace CODE, XXX, YYY with the user's answers, and SERVE_DIR with `dashboard.serve_dir` from preflight.

### Step 3: Summary

Using the preflight + lookup data, present:

```
Flight Mode: [airline_name] [airline_code][flight_number if known]
Route: [origin] → [destination] (~[duration]h)
WiFi: [provider] · Rating: [rating]
API Status: [verdict] via [egress_country]
Network: [ssid] ([type])
Dashboard: [dashboard_url]

Calibration:
- Micro-task batch: [batch_size]
- Checkpoint every: [checkpoint_interval] tasks
- Git commit every: [commit_interval] tasks

[If weak_zone exists:]
Connectivity Timeline:
  Hours 0-[start]: Strong signal
  Hours [start]-[end]: WEAK ZONE — [reason]
  Hours [end]-[duration]: Signal recovery

[If api.warning exists:]
Warning: [warning text]
```

### HARD GATE — MANDATORY CONFIRMATION

You MUST ask: **"Activate flight mode? (y/n)"**

Wait for the user's explicit response. Do NOT proceed without it.

- **"n"** → Say: "Flight mode not activated. Dashboard is live at [url]." STOP HERE.
- **"y"** → Continue to Step 4.

### Step 4: Activate

Run the activation script (do NOT write FLIGHT_MODE.md directly):
```bash
echo '{"airline_code":"...","airline_name":"...","origin":"...","destination":"...","provider":"...","rating":"...","stable_window":"...","duration_hours":N,"api_verdict":"...","egress_country":"...","dashboard_url":"...","weak_zone":ZONE_OR_NULL,"calibration":{...},"cwd":"CWD","plugin_dir":"${CLAUDE_PLUGIN_ROOT}"}' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/flight-on-activate.sh"
```

Fill in all values from the preflight + lookup results. Set `cwd` to the current working directory.

### Step 5: Check .gitignore & Begin

**Check .gitignore:** If the repo has a `.gitignore`, check whether `FLIGHT_MODE.md` and `.flight-state.md` are listed. If not, tell the user:

```
Note: FLIGHT_MODE.md and .flight-state.md are runtime files.
I recommend adding them to .gitignore:

  FLIGHT_MODE.md
  .flight-state.md
  .flight-state-*.md

Want me to add these? (y/n)
```

If the user agrees, append them.

**Get the task:** If the user hasn't already said what they want to work on, ask:
```
What do you want to work on this flight?
```

**Decompose into micro-tasks** and update `.flight-state.md` with the plan.

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
