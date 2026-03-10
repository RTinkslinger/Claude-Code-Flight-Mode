# Flight Mode

A Claude Code plugin that makes Claude resilient on unreliable in-flight WiFi. It changes **how Claude thinks** — micro-task decomposition, automatic checkpointing, context budgeting — so you can code productively at 35,000 feet without losing work to WiFi drops.

## How It Works

Flight Mode is a behavioral protocol, not a model switch. When activated:

1. **Micro-task decomposition** — Every request is broken into small, self-contained tasks (1-2 tool calls each). If WiFi drops mid-task, the codebase stays in a valid state.
2. **Checkpoint discipline** — Progress is saved to `.flight-state.md` and committed to git at intervals calibrated to your WiFi quality.
3. **Context budgeting** — Claude reads files sparingly, avoids speculative exploration, and warns when context is running low.
4. **Auto-recovery** — If a session drops, the next session reads the checkpoint file and resumes exactly where you left off.
5. **Stop hook safety net** — If Claude Code exits unexpectedly, uncommitted changes are auto-committed with a `flight:` prefix.

## V2 Features

### Deterministic Preflight

When you run `/flight-on`, a preflight orchestrator runs **before Claude sees the prompt** — no LLM drift, no skipped steps:

1. **Flight parsing** — Extracts airline code, origin, destination from your input (e.g., `CX HKG-LAX` or `CX884`)
2. **Network detection** — Identifies WiFi SSID and matches against known airline/airport networks
3. **API geo-check** — Tests Claude API reachability, measures latency, checks egress country for geo-blocking
4. **Route corridor matching** — Looks up flight duration, satellite coverage waypoints, and weak signal zones
5. **Dashboard launch** — Starts a live connectivity dashboard at `http://localhost:8234`

All results are injected as JSON into Claude's context. Claude then presents a summary, asks for confirmation, and activates only when you say yes.

### Live Dashboard

A browser-based dashboard at `http://localhost:8234` showing:

- **Connectivity timeline** — SVG chart with satellite coverage waypoints along your route
- **Weak zone overlay** — Visual indication of expected signal drops (e.g., central Pacific on transpacific flights)
- **Live latency chart** — Real-time ping and HTTP latency during the flight
- **Status cards** — API status, current flight phase, next event, session stats
- **Drop log** — Table of detected connectivity drops with duration and severity

### Route Corridors

Pre-mapped signal coverage for common flight corridors:

- US Domestic, US-Europe, Transpacific North/South, Transatlantic North/South
- Europe-Asia, Europe-Middle East, Middle East-Asia, Oceania routes
- Each corridor has waypoints with latitude, longitude, estimated signal strength, and phase notes

## WiFi Ratings

The plugin profiles 40+ airlines and calibrates behavior to your connection:

| Rating | Examples | Behavior |
|---|---|---|
| EXCELLENT | Air France (Starlink), United (Starlink) | Up to 5 tasks queued, checkpoint every 4-5 |
| GOOD | Delta (domestic), JetBlue, Air Canada | Up to 3 queued, checkpoint every 3-4 |
| USABLE | Cathay Pacific, Emirates, Singapore Airlines | 1-2 at a time, checkpoint every 2-3 |
| CHOPPY | American (widebody), Lufthansa (legacy) | 1 at a time, checkpoint every 1-2 |
| POOR | Frontier, Ryanair, Asian LCCs | 1 task, minimal reads, checkpoint after every task |

Unknown carriers default to USABLE.

## Installation

### Option A: Local plugin (recommended for now)

```bash
# Clone the repo
git clone https://github.com/RTinkslinger/Claude-Code-Flight-Mode.git

# Run Claude Code with the plugin loaded
claude --plugin-dir /path/to/Claude-Code-Flight-Mode
```

Or add an alias to your shell config:

```bash
# Add to ~/.zshrc or ~/.bashrc
alias flight-claude='claude --plugin-dir "/path/to/Claude-Code-Flight-Mode"'
```

### Option B: Marketplace (when available)

```bash
claude plugin install flight-mode
```

### One-time setup: CLAUDE.md snippet

Add this to `~/.claude/CLAUDE.md` so Claude auto-detects flight mode on recovery:

```markdown
## Flight Mode
If `FLIGHT_MODE.md` exists in this repo root, read it before doing anything else.
If `.flight-state.md` exists with incomplete tasks, resume from the last checkpoint.
```

This is optional but enables seamless session recovery across all repos.

## Usage

### Activate

```
/flight-on [airline] [route]
```

Examples:
```
/flight-on CX HKG-LAX
/flight-on DL JFK-LAX
/flight-on CX884
/flight-on              (will ask for details)
```

Claude will:
- Run the preflight orchestrator (parse, network detect, API check, dashboard start, route lookup)
- Present a summary with WiFi rating, calibration, connectivity timeline, and weak zones
- Ask **"Activate flight mode? (y/n)"** — a hard gate, nothing happens without your confirmation
- On "y": create `FLIGHT_MODE.md` and `.flight-state.md`, check `.gitignore`, ask for your task
- On "n": stop (dashboard stays live for reference)

### Check connectivity

```
/flight-check
```

Standalone check — tests API reachability, latency, geo-IP, and network type without activating flight mode.

### Work normally

Just tell Claude what to do. The protocol runs in the background:
- Tasks are executed one at a time with checkpoints
- Git commits use a `flight:` prefix
- `.flight-state.md` tracks progress for recovery
- Context warnings appear at 45%, 65%, and 85% usage

### Deactivate

```
/flight-off
```

Claude will:
- Show a summary of work done (tasks, files, commits)
- Offer to squash `flight:` commits into a single clean commit
- Archive the state file
- Remove `FLIGHT_MODE.md`

### Recover from a drop

If WiFi drops and your session dies:

1. Reopen Claude Code (with `--plugin-dir` or the alias)
2. If you added the CLAUDE.md snippet, Claude auto-detects the state and resumes
3. If not, say "read FLIGHT_MODE.md" and Claude picks up where it left off

## What gets created in your repo

| File | Purpose | Persists? |
|---|---|---|
| `FLIGHT_MODE.md` | Signals flight mode is active + condensed protocol | Removed by `/flight-off` |
| `.flight-state.md` | Task progress, recovery instructions | Archived by `/flight-off` |
| `.flight-state-YYYY-MM-DD.md` | Archived state from previous sessions | Yes (add to `.gitignore`) |

Add these to `.gitignore` — `/flight-on` will offer to do this for you:

```
FLIGHT_MODE.md
.flight-state.md
.flight-state-*.md
```

## Plugin Structure

```
flight-mode/
├── .claude-plugin/plugin.json          # Plugin manifest (v2.0.0)
├── skills/
│   ├── flight-on/SKILL.md              # Activation: preflight + protocol
│   ├── flight-off/SKILL.md             # Deactivation: summary + cleanup
│   └── flight-check/SKILL.md           # Standalone connectivity check
├── hooks/hooks.json                    # Stop, PreToolUse, PostToolUse hooks
├── scripts/
│   ├── flight-on-preflight.sh          # Orchestrator: runs all checks deterministically
│   ├── parse-flight.sh                 # Extract airline, origin, destination from input
│   ├── network-detect.sh               # Identify WiFi SSID and type
│   ├── flight-check.sh                 # API reachability, latency, geo-IP
│   ├── flight-on-lookup.sh             # Airline profile + route corridor matching
│   ├── flight-on-activate.sh           # Create FLIGHT_MODE.md + .flight-state.md
│   ├── dashboard-server.sh             # HTTP server for live dashboard (port 8234)
│   ├── block-direct-flight-mode.sh     # PreToolUse hook: prevent direct FLIGHT_MODE.md writes
│   ├── stop-checkpoint.sh              # Stop hook: auto-commit on session end
│   ├── context-monitor.sh              # PostToolUse hook: context budget tracking
│   └── measure-latency.sh             # Latency measurement for CSV logging
├── data/
│   ├── airline-profiles.json           # 40+ carrier WiFi profiles with ratings
│   ├── airline-codes.json              # IATA code → airline name mapping
│   ├── airport-codes.json              # IATA code → city/country mapping
│   ├── route-corridors.json            # Pre-mapped signal coverage corridors
│   ├── provider-egress.json            # WiFi provider → egress country mapping
│   ├── supported-countries.json        # Claude API geo-availability
│   ├── wifi-ssids.json                 # Known airline/airport WiFi SSIDs
│   └── flight-profiles.md             # Compact lookup table for Claude
├── templates/
│   ├── dashboard.html                  # Live dashboard template (SVG charts, status cards)
│   └── claude-md-snippet.md            # 3-line CLAUDE.md addition for users
├── tests/
│   ├── run-tests.sh                    # Full test suite (74 core tests)
│   ├── test-v2-parse-flight.sh         # V2: flight parsing tests (24)
│   ├── test-v2-network-detect.sh       # V2: network detection tests (17)
│   ├── test-v2-flight-check.sh         # V2: API check tests (18)
│   ├── test-v2-data-validation.sh      # V2: data file validation (25)
│   ├── test-v2-dashboard.sh            # V2: dashboard server tests (15)
│   └── phase3-log-capture.sh           # Live test log capture script
└── docs/
    ├── system-plan-v2.md               # Architecture and design
    └── plans/                          # Sprint plans and test results
```

## How the protocol layers work

| Layer | File | Purpose | When read |
|---|---|---|---|
| 1 | `/flight-on` SKILL.md | Full protocol + preflight injection | Once, at activation |
| 2 | `FLIGHT_MODE.md` | Condensed protocol (~20 lines) | On recovery |
| 3 | `~/.claude/CLAUDE.md` snippet | "Read FLIGHT_MODE.md if it exists" | Every session start |
| 4 | Hooks | Auto-checkpoint, context monitor, write guard | Every tool call / session end |

Each layer does one job. No duplication. Hooks enforce mechanically; protocol text covers what hooks can't.

## Testing

```bash
# Full test suite (173 tests)
bash tests/run-tests.sh

# V2-specific tests individually
bash tests/test-v2-parse-flight.sh
bash tests/test-v2-network-detect.sh
bash tests/test-v2-flight-check.sh
bash tests/test-v2-data-validation.sh
bash tests/test-v2-dashboard.sh
```

## License

MIT
