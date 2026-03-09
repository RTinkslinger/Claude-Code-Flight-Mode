# In-Flight Test Plan — Expected Behavior Tests

**Purpose:** Manual test plan to run while on actual flight WiFi. Combines plugin behavior testing with live latency measurement to validate the system AND collect data for V2 auto-detection.

**Current flight:** Cathay Pacific HKG-LAX (USABLE rating)

---

## Pre-Flight Setup (before testing)

1. Source the alias: `source ~/.zshrc`
2. Navigate to any git repo you want to test in
3. Start latency baseline:
   ```bash
   cd "/Users/Aakash/Claude Projects/Flight Mode"
   bash scripts/measure-latency.sh --header > measurements/2026-03-10-cathay-hkg-lax.csv
   bash scripts/measure-latency.sh >> measurements/2026-03-10-cathay-hkg-lax.csv
   ```

---

## Part 1: Latency Baseline (run FIRST, takes 2 min)

Run these from any terminal — captures your current WiFi conditions:

```bash
# Quick network snapshot
ping -c 5 8.8.8.8
curl -o /dev/null -s -w 'HTTP roundtrip: %{time_total}s\n' https://api.anthropic.com
dig api.anthropic.com +stats | grep "Query time"
```

Record the results. Then run the measurement script:
```bash
bash "/Users/Aakash/Claude Projects/Flight Mode/scripts/measure-latency.sh" >> measurements/2026-03-10-cathay-hkg-lax.csv
```

**Repeat this every 15-30 min throughout your testing session.** This data feeds V2 auto-detection.

---

## Part 2: Plugin Behavior Tests

Open a test repo (any repo with git, or create a throwaway one):

```bash
mkdir ~/test-flight-mode && cd ~/test-flight-mode && git init && git commit --allow-empty -m "init"
flight-claude
```

### Test 1: Activation — Known Carrier

**Do:** Type `/flight-on Cathay Pacific HKG-LAX`

**Expected:**
- [ ] Shows WiFi rating: **USABLE**
- [ ] Shows stable window: **20-40 min**
- [ ] Shows calibration: micro-task batch 1-2, checkpoint every 2-3 tasks
- [ ] Mentions key note about Cathay (600-900ms latency, 1-2 drops/flight)
- [ ] Creates `FLIGHT_MODE.md` in repo root
- [ ] `FLIGHT_MODE.md` contains airline, rating, condensed 7-rule protocol
- [ ] Asks what you want to work on OR asks about .gitignore

**Log:** Note actual wall-clock time for the activation response (measures API latency under flight WiFi).

### Test 2: Activation — Unknown Carrier

**Do:** Start a fresh session. Type `/flight-on Garuda Indonesia DPS-SIN`

**Expected:**
- [ ] Falls back to UNKNOWN / USABLE rating
- [ ] Notes carrier is not profiled
- [ ] Still creates FLIGHT_MODE.md with USABLE defaults
- [ ] Proceeds with standard protocol

### Test 3: Task Decomposition

**Do:** After activation, say: "Create a hello world Python script with a test file"

**Expected:**
- [ ] Decomposes into numbered micro-tasks (e.g., 1. Create hello.py, 2. Create test_hello.py, 3. Commit)
- [ ] Writes task list to `.flight-state.md`
- [ ] Shows plan and asks to confirm before starting
- [ ] Each micro-task is 1-2 tool calls max

### Test 4: Checkpoint Cadence (USABLE = every 2-3 tasks)

**Do:** Let Claude work through 2-3 micro-tasks.

**Expected:**
- [ ] After task 2 or 3: updates `.flight-state.md` with `[x]` marks
- [ ] Makes a git commit with `flight:` prefix
- [ ] Stages specific files (NOT `git add -A`)
- [ ] Commit message describes what was done
- [ ] `.flight-state.md` has updated "Last Action" and "Files Modified"

**Log:** Note wall-clock time per micro-task.

### Test 5: Git Discipline

**Do:** Check git log after a few tasks.

```bash
git log --oneline
```

**Expected:**
- [ ] All flight commits have `flight:` prefix
- [ ] Commits are granular (one per checkpoint, not one per task)
- [ ] No `git add -A` (check with `git show --stat` — only relevant files)

### Test 6: Context Budget Awareness

**Do:** In a long session, observe if Claude mentions context.

**Expected:**
- [ ] First half of session: no context warnings (silent below 45%)
- [ ] If session runs long: warns about context budget
- [ ] Suggests checkpointing or new session when context is heavy

### Test 7: Recovery from WiFi Drop (THE CRITICAL TEST)

**Do:**
1. Let Claude work through 1-2 tasks
2. **Kill the terminal** (Cmd+W, or `kill` the process)
3. Check: `cat .flight-state.md` — is the state saved?
4. Check: `git log --oneline` — was there an auto-checkpoint commit?
5. Reopen: `flight-claude`
6. See if Claude reads FLIGHT_MODE.md → .flight-state.md → offers to resume

**Expected:**
- [ ] `.flight-state.md` has task progress from before the kill
- [ ] Auto-checkpoint commit exists (from stop hook) — if there were uncommitted changes
- [ ] New session detects FLIGHT_MODE.md (if CLAUDE.md snippet is in global config)
- [ ] Claude reads `.flight-state.md` and identifies next incomplete task
- [ ] Resumes without re-reading files it already processed
- [ ] No codebase corruption or half-written files

**Log:** Time between kill and recovery (measures how fast you can get back to work).

### Test 8: Recovery WITHOUT CLAUDE.md Snippet

**Do:** Temporarily remove the flight mode snippet from `~/.claude/CLAUDE.md`, kill and restart.

**Expected:**
- [ ] Hooks still fire (they don't depend on the snippet)
- [ ] But Claude does NOT auto-detect FLIGHT_MODE.md (no snippet to tell it)
- [ ] You'd have to say "read FLIGHT_MODE.md" manually
- [ ] This confirms the snippet's value — it's small but important

### Test 9: Deactivation — All Tasks Complete

**Do:** After all tasks done, type `/flight-off`

**Expected:**
- [ ] Shows summary: tasks completed, files modified, flight commit count
- [ ] Lists all `flight:` commits
- [ ] Offers to squash if 2+ flight commits
- [ ] If squash accepted: single clean commit replaces all flight commits
- [ ] Removes `FLIGHT_MODE.md`
- [ ] Archives `.flight-state.md` to `.flight-state-YYYY-MM-DD.md`
- [ ] Confirms "Flight mode off"

### Test 10: Deactivation — Incomplete Tasks

**Do:** Activate, start a task, then `/flight-off` before completing all micro-tasks.

**Expected:**
- [ ] Summary clearly lists incomplete tasks
- [ ] Notes them for normal-session pickup
- [ ] Still offers squash for completed work
- [ ] Archived `.flight-state.md` preserves incomplete task list

### Test 11: Double Activation

**Do:** Run `/flight-on` when FLIGHT_MODE.md already exists.

**Expected:**
- [ ] Detects existing flight mode session
- [ ] Offers to resume existing or restart fresh
- [ ] Does NOT overwrite .flight-state.md without asking

### Test 12: Deactivation When Not Active

**Do:** Without FLIGHT_MODE.md, run `/flight-off`

**Expected:**
- [ ] Reports "flight mode not active" or similar
- [ ] Does nothing destructive

---

## Part 3: Live WiFi Stress Tests

These test behavior under actual degraded conditions.

### Test 13: Work During Connectivity Drop

**Do:** Start a task, watch for WiFi dropping (check `ping 8.8.8.8` in another terminal).

**Expected:**
- [ ] If drop happens mid-tool-call: Claude Code shows error/timeout
- [ ] On reconnect: `.flight-state.md` tells you where to resume
- [ ] Stop hook may have fired (check `git log` for auto-checkpoint)
- [ ] No partial file writes corrupting code

**Log:** Duration of drop, what Claude was doing when it dropped.

### Test 14: Rapid Successive Drops

**Do:** If WiFi is unstable, test working through 2-3 micro-drops.

**Expected:**
- [ ] Each recovery picks up cleanly from .flight-state.md
- [ ] No accumulated state corruption
- [ ] Context monitor resets for new session
- [ ] Flight commits accumulate but stay clean

### Test 15: Pre-Commit Hook Interaction

**Do:** In a repo with pre-commit hooks (e.g., linting), let Claude make a flight commit.

**Expected:**
- [ ] If pre-commit passes: normal commit
- [ ] If pre-commit fails: Claude notes it in .flight-state.md, skips commit, continues
- [ ] Does NOT burn context debugging the hook failure
- [ ] Stop hook uses `--no-verify` (emergency checkpoint bypasses pre-commit)

---

## Part 4: Latency Measurement Throughout

Run this command every 15-30 min during your testing:

```bash
bash "/Users/Aakash/Claude Projects/Flight Mode/scripts/measure-latency.sh" >> "/Users/Aakash/Claude Projects/Flight Mode/measurements/2026-03-10-cathay-hkg-lax.csv"
```

Also log subjectively:
- **Tool call responsiveness** — how many seconds per Read/Edit?
- **Drop frequency** — how often does WiFi cut out?
- **Drop duration** — how long until reconnect?
- **Satellite handoff** — any patterns in when drops occur? (Pacific crossing = common)

### Quick Latency Check (one-liner)

```bash
echo "$(date +%H:%M) | ping: $(ping -c 3 -W 5 8.8.8.8 2>/dev/null | tail -1 | awk -F'/' '{print $5}')ms | http: $(curl -o /dev/null -s -w '%{time_total}' --max-time 10 https://api.anthropic.com)s"
```

---

## Part 5: Post-Test Data Collection

After all testing, fill in the flight measurement log:

```bash
cat "/Users/Aakash/Claude Projects/Flight Mode/measurements/2026-03-10-cathay-hkg-lax.csv"
```

And create a summary in `measurements/2026-03-10-cathay-hkg-lax.md`:
- Total test duration
- Number of drops observed
- Average latency
- Profile validation: does USABLE match reality?
- Recommended adjustment: none / upgrade / downgrade
- Notable observations

---

## Scoring Guide

| Test | Weight | Pass Criteria |
|---|---|---|
| T1-T2: Activation | High | Correct rating, files created, protocol shown |
| T3-T4: Task execution | High | Decomposition works, checkpoints at right cadence |
| T5: Git discipline | Medium | flight: prefix, specific staging, clean history |
| T6: Context budget | Low | Hard to trigger in short test — observe over time |
| T7: Recovery (drop) | **Critical** | This is the whole point of the plugin |
| T8: Recovery (no snippet) | Medium | Validates graceful degradation |
| T9-T10: Deactivation | High | Clean summary, squash works, cleanup complete |
| T11-T12: Edge cases | Medium | No crashes, graceful handling |
| T13-T14: Live WiFi stress | **Critical** | Real-world resilience proof |
| T15: Pre-commit hooks | Medium | Doesn't break user's existing workflow |

**Minimum viable pass:** T1, T3, T4, T7, T9 all green. T7 is the make-or-break test.
