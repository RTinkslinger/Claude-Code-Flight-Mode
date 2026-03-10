# Deterministic Flight-On Redesign

**Date:** 2026-03-10
**Status:** Approved
**Problem:** LLM drift — Claude skips scripts, improvises flow, activates without confirmation
**Solution:** Two-phase orchestrator with command injection (`!`command``)

---

## Problem Statement

Test Scenario 1 (2026-03-10) revealed that the current SKILL.md-based flow fails catastrophically. Claude skipped 5 of 8 steps:

| Step | Expected | Actual |
|------|----------|--------|
| parse-flight.sh | Run script | Used MCP web search instead |
| network-detect.sh | Run script | Never ran |
| flight-check.sh | Run script | Never ran |
| Dashboard start | localhost:8234 | Never started |
| "Activate? (y/n)" | Ask user | Skipped, activated directly |
| FLIGHT_MODE.md | Only on confirmation | Written without asking |

**Root cause:** SKILL.md text is suggestive ("Run this command..."). Claude interprets this as optional and improvises. Skills are prompt text, and prompt text drifts.

---

## Architecture: Two-Phase Orchestrator

### Principle

Replace "instructions to run scripts" with "scripts that run before Claude sees the prompt." The plugin system's `!`command`` feature executes shell commands at skill load time and injects output as static text. Claude receives **data**, not instructions to gather data.

### Script Architecture

```
User types /flight-on [args]
         │
         ▼
┌─────────────────────────────┐
│  flight-on-preflight.sh     │  ← runs via !`command` (deterministic)
│  ┌─ parse-flight.sh         │
│  ├─ network-detect.sh       │
│  ├─ flight-check.sh         │
│  ├─ dashboard-server.sh     │
│  └─ lookup (if data ready)  │
└────────────┬────────────────┘
             │ JSON output injected into prompt
             ▼
┌─────────────────────────────┐
│  Claude (thin layer)        │
│  ├─ Read preflight results  │
│  ├─ Ask 0-2 questions       │  ← only if flight info incomplete
│  ├─ Run lookup script       │  ← only if needed (1 bash call)
│  ├─ Present summary         │
│  └─ Ask "Activate? (y/n)"   │  ← HARD GATE
└────────────┬────────────────┘
             │ user confirms "y"
             ▼
┌─────────────────────────────┐
│  flight-on-activate.sh      │  ← Claude runs (1 bash call)
│  ├─ Write FLIGHT_MODE.md    │
│  └─ Write .flight-state.md  │
└─────────────────────────────┘
```

### Scripts

#### 1. `scripts/flight-on-preflight.sh`

**Trigger:** `!`command`` in SKILL.md — runs at skill load, 100% deterministic.

**Input:** `$1` = user arguments (may be empty), `$2` = plugin dir

**Executes (in order):**
1. `parse-flight.sh` with user arguments
2. `network-detect.sh`
3. `flight-check.sh`
4. `dashboard-server.sh start`
5. If airline_code AND origin AND destination all resolved → also runs lookup internally

**Output:** Single JSON blob:
```json
{
  "parse": {
    "airline_code": "CX",
    "airline_name": "Cathay Pacific",
    "origin": "BLR",
    "destination": "HKG",
    "provider": "gogo",
    "confidence": "high",
    "needs_route": false
  },
  "network": {
    "ssid": "Courtyard_GUEST",
    "type": "other",
    "provider": null,
    "confidence": "low"
  },
  "api": {
    "verdict": "GO",
    "api_reachable": true,
    "api_latency_ms": 46,
    "egress_country": "US",
    "egress_city": "Santa Monica",
    "country_supported": true,
    "warning": null
  },
  "dashboard": {
    "status": "started",
    "url": "http://localhost:8234",
    "pid": 12345,
    "serve_dir": "/tmp/flight-mode-dashboard-abc123"
  },
  "lookup": {
    "rating": "USABLE",
    "stable_window": "20-40",
    "note": "600-900ms latency; 1-2 drops/flight",
    "corridor": "intra-asia",
    "duration_hours": 5.5,
    "waypoints": [...],
    "weak_zone": null,
    "calibration": {
      "batch_size": "1-2",
      "checkpoint_interval": "2-3",
      "commit_interval": "2-3"
    }
  },
  "ready": true,
  "missing": []
}
```

If lookup couldn't run (missing airline or route):
```json
{
  "parse": { ... },
  "network": { ... },
  "api": { ... },
  "dashboard": { ... },
  "lookup": null,
  "ready": false,
  "missing": ["route"]
}
```

**Timeout:** 20s (flight-check.sh has internal timeouts on network calls).

#### 2. `scripts/flight-on-lookup.sh`

**Trigger:** Claude runs via Bash — only when preflight `ready` is false.

**Input:** JSON on stdin:
```json
{
  "airline_code": "CX",
  "origin": "BLR",
  "destination": "HKG",
  "plugin_dir": "/path/to/plugin",
  "dashboard_dir": "/tmp/flight-mode-dashboard-abc123"
}
```

**Executes:**
1. Read `data/airline-profiles.json` — find airline rating, stable window, notes
2. Read `data/provider-egress.json` — get provider egress info
3. Read `data/route-corridors.json` — match route to closest corridor
4. Compute calibration from rating
5. Write `route-data.json` to dashboard directory

**Output:** Lookup JSON (same structure as preflight's `lookup` field).

#### 3. `scripts/flight-on-activate.sh`

**Trigger:** Claude runs via Bash — only after user explicitly says "y".

**Input:** JSON on stdin:
```json
{
  "airline_code": "CX",
  "airline_name": "Cathay Pacific",
  "origin": "BLR",
  "destination": "HKG",
  "provider": "gogo",
  "rating": "USABLE",
  "stable_window": "20-40",
  "duration_hours": 5.5,
  "api_verdict": "GO",
  "egress_country": "US",
  "dashboard_url": "http://localhost:8234",
  "weak_zone": null,
  "calibration": { "batch_size": "1-2", "checkpoint_interval": "2-3", "commit_interval": "2-3" },
  "cwd": "/path/to/user/repo",
  "plugin_dir": "/path/to/plugin"
}
```

**Writes:**
1. `FLIGHT_MODE.md` in `cwd` — flight info + condensed protocol
2. `.flight-state.md` in `cwd` — initial session state (awaiting task)

**Output:**
```json
{
  "status": "activated",
  "flight_mode_path": "/path/to/FLIGHT_MODE.md",
  "flight_state_path": "/path/to/.flight-state.md"
}
```

### Data File Change

**New file: `data/airline-profiles.json`**

JSON mirror of the Quick Lookup Table in `flight-profiles.md`. Enables programmatic lookup by scripts (markdown tables can't be parsed reliably by shell scripts).

```json
{
  "_note": "Programmatic mirror of flight-profiles.md Quick Lookup Table",
  "profiles": {
    "DL": { "name": "Delta", "rating_domestic": "GOOD", "rating_longhaul": "USABLE", "stable_window_domestic": "45-90", "stable_window_longhaul": "20-40", "note": "Upload <1 Mbps; free for SkyMiles" },
    "CX": { "name": "Cathay Pacific", "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "600-900ms latency; 1-2 drops/flight" }
  },
  "default": { "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "Unknown carrier — using conservative defaults" },
  "calibration": {
    "EXCELLENT": { "batch_size": "up to 5", "checkpoint_interval": "4-5", "commit_interval": "4-5" },
    "GOOD":      { "batch_size": "up to 3", "checkpoint_interval": "3-4", "commit_interval": "3-4" },
    "USABLE":    { "batch_size": "1-2", "checkpoint_interval": "2-3", "commit_interval": "2-3" },
    "CHOPPY":    { "batch_size": "1", "checkpoint_interval": "1-2", "commit_interval": "1-2" },
    "POOR":      { "batch_size": "1, minimal reads", "checkpoint_interval": "1", "commit_interval": "1" },
    "UNKNOWN":   { "batch_size": "1-2", "checkpoint_interval": "2-3", "commit_interval": "2-3" }
  }
}
```

### SKILL.md Structure

```markdown
---
name: flight-on
description: Activate flight mode for resilient coding on unreliable in-flight WiFi.
argument-hint: [flight-code or airline route]
user-invocable: true
allowed-tools: Read, Bash, Write, Edit
---

# Flight Mode — Activation

## Preflight Results

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/flight-on-preflight.sh" "$ARGUMENTS" "${CLAUDE_PLUGIN_ROOT}" 2>/dev/null || echo '{"error":"preflight failed"}'`

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

After activation, check .gitignore and ask about adding flight files.
Then ask the user what they want to work on and decompose into micro-tasks.

## Behavioral Protocol (Active After Activation)

[Rules 1-7 unchanged from current SKILL.md]
```

### Safety Hook

**New PreToolUse hook in `hooks.json`:**

Blocks direct `Write` to `FLIGHT_MODE.md` — forces use of the activate script. Deterministic backstop against LLM drift.

```bash
#!/bin/bash
# block-direct-flight-mode.sh
# Prevents Claude from writing FLIGHT_MODE.md directly.
# Must use flight-on-activate.sh instead.
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if echo "$FILE_PATH" | grep -q "FLIGHT_MODE.md"; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "FLIGHT_MODE.md must be created by flight-on-activate.sh, not written directly. Run the activate script."
  }
}
EOF
  exit 0
fi

exit 0
```

Hook registration in `hooks.json`:
```json
{
  "matcher": "Write",
  "hooks": [{
    "type": "command",
    "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/block-direct-flight-mode.sh\"",
    "timeout": 5
  }]
}
```

---

## UX Matrix

| User Input | Preflight Resolves | Claude Asks | Claude Script Calls | Total Time |
|---|---|---|---|---|
| `/flight-on CX HKG-LAX` | Everything | Just confirmation | 1 (activate) | ~12s load + instant |
| `/flight-on CX624` | Parse+env+dashboard | Route | 2 (lookup+activate) | ~12s load + 1 question |
| `/flight-on` | Env+dashboard only | Flight + maybe route | 2 (lookup+activate) | ~12s load + 1-2 questions |

---

## Files Changed

| File | Action | Purpose |
|------|--------|---------|
| `scripts/flight-on-preflight.sh` | NEW | Orchestrator — runs all env scripts at skill load |
| `scripts/flight-on-lookup.sh` | NEW | Profile + corridor lookup |
| `scripts/flight-on-activate.sh` | NEW | Writes FLIGHT_MODE.md + .flight-state.md |
| `scripts/block-direct-flight-mode.sh` | NEW | Safety hook — blocks direct Write |
| `data/airline-profiles.json` | NEW | Programmatic mirror of flight-profiles.md table |
| `skills/flight-on/SKILL.md` | REWRITE | Thin layer with `!`command`` injection |
| `hooks/hooks.json` | MODIFY | Add PreToolUse Write hook |

No changes to existing scripts (parse-flight.sh, network-detect.sh, flight-check.sh, dashboard-server.sh). They are called by the orchestrator.

---

## Test Plan

Re-run Test Scenario 1 after implementation:
1. Normal ground WiFi, `/flight-on CX HKG-LAX`
2. Verify: all 4 scripts run (visible in preflight JSON output)
3. Verify: dashboard at localhost:8234 with route data
4. Verify: summary shown with correct data
5. Verify: "Activate? (y/n)" asked
6. Verify: user says "n" → no FLIGHT_MODE.md created
7. Verify: dashboard remains running

Additional scenarios:
- `/flight-on` with no args → asks for flight, then proceeds
- `/flight-on CX624` → asks for route only
- User says "y" → FLIGHT_MODE.md + .flight-state.md created correctly
- Direct Write to FLIGHT_MODE.md → blocked by hook
