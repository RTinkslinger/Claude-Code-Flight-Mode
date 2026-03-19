---
name: flight-off
description: Deactivate flight mode. Summarizes work done, offers to squash flight commits, cleans up runtime files.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Flight Mode — Deactivation Protocol

You are deactivating flight mode. This produces a summary, offers commit squash, and cleans up runtime files.

## Step 1: Read Flight State

Read these files:
- `FLIGHT_MODE.md` — get airline, route, rating, activation time
- `.flight-state.md` — get task list, completion status, files modified

If neither file exists, tell the user: "Flight mode doesn't appear to be active (no FLIGHT_MODE.md found)." and stop.

## Step 2: Count Flight Commits

```bash
git log --oneline | grep "flight:" | wc -l
```

Also get the list of flight commits for the summary:
```bash
git log --oneline | grep "flight:"
```

## Step 3: Show Summary

Present a concise flight summary:

```
Flight Mode Summary
━━━━━━━━━━━━━━━━━━
Airline: [airline] [route]
WiFi Rating: [RATING]
Session: [activation time] → now

Tasks: [completed]/[total] completed
Files modified: [list]
Flight commits: [N]

[If incomplete tasks exist:]
Incomplete tasks:
- [ ] [task description]
- [ ] [task description]
```

## Step 4: Offer Commit Squash

If there are 2+ flight commits, offer to squash:

```
You have [N] flight: commits. Squash them into a single commit?

This will combine:
  [list of flight: commit messages]

Into one clean commit. (y/n)
```

**If yes — squash using non-interactive approach:**

First, verify the squash target is safe:
```bash
# Find the first flight: commit and get its parent
FIRST_FLIGHT=$(git log --oneline --reverse | grep "flight:" | head -1 | cut -d' ' -f1)
BEFORE_FLIGHT=$(git rev-parse "${FIRST_FLIGHT}^" 2>/dev/null)
```

If `BEFORE_FLIGHT` is empty (all commits are flight commits), tell the user:
"All commits in this repo are flight commits — cannot squash safely. Skipping."

Otherwise, proceed:
```bash
git reset --soft $BEFORE_FLIGHT
git commit -m "feat: [summary based on completed tasks]"
```

After squashing, **verify the result**:
```bash
git log --oneline -5
```

Show the user the result and confirm the squash looks correct.

Generate a meaningful commit message from the completed micro-tasks — not just "flight work" but a real description like "feat: add user authentication middleware and tests" or "fix: resolve race condition in WebSocket handler".

**If no** — leave commits as-is. They can always be squashed later with `git rebase -i` on stable ground.

**If only 0-1 flight commits** — skip this step (nothing to squash).

## Step 5: Handle Incomplete Tasks

If any micro-tasks are still incomplete:

```
[N] tasks remain incomplete. These can be finished in a normal session:
- [ ] [task description]
- [ ] [task description]

I'll note these in the archived flight state for reference.
```

## Step 6: Archive Flight State

Rename `.flight-state.md` to preserve it:

```bash
mv .flight-state.md ".flight-state-$(date +%Y-%m-%d).md"
```

This keeps a record of the flight session. The dated file won't trigger flight mode recovery (the CLAUDE.md snippet checks for `.flight-state.md` specifically).

## Step 6.5: Stop Dashboard Server

Stop the live dashboard server if it's running:

```bash
echo '{"command":"stop","cwd":"'$(pwd)'"}' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/dashboard-server.sh"
```

This kills the Python HTTP server on port 8234 and cleans up the serve directory.

## Step 7: Remove FLIGHT_MODE.md

```bash
rm FLIGHT_MODE.md
```

This is the signal that flight mode is OFF. Hooks that check for `FLIGHT_MODE.md` become no-ops.

## Step 8: Confirm

```
Flight mode off. Back to normal operations.
[If there were incomplete tasks: "Remaining tasks noted in .flight-state-YYYY-MM-DD.md"]
```
