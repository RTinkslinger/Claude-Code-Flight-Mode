# Flight Mode

A Claude Code plugin that makes Claude resilient on unreliable in-flight WiFi. It changes **how Claude thinks** — micro-task decomposition, automatic checkpointing, context budgeting — so you can code productively at 35,000 feet without losing work to WiFi drops.

## How It Works

Flight Mode is a behavioral protocol, not a model switch. When activated:

1. **Micro-task decomposition** — Every request is broken into small, self-contained tasks (1-2 tool calls each). If WiFi drops mid-task, the codebase stays in a valid state.
2. **Checkpoint discipline** — Progress is saved to `.flight-state.md` and committed to git at intervals calibrated to your WiFi quality.
3. **Context budgeting** — Claude reads files sparingly, avoids speculative exploration, and warns when context is running low.
4. **Auto-recovery** — If a session drops, the next session reads the checkpoint file and resumes exactly where you left off.
5. **Stop hook safety net** — If Claude Code exits unexpectedly, uncommitted changes are auto-committed with a `flight:` prefix.

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
/flight-on Cathay Pacific HKG-LAX
/flight-on Delta JFK-LHR
/flight-on    (will ask for details)
```

Claude will:
- Look up the airline's WiFi profile
- Show the rating and calibration settings
- Create `FLIGHT_MODE.md` and `.flight-state.md` in your repo
- Ask what you want to work on
- Decompose into micro-tasks and start working

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
- Show a summary of work done
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
├── .claude-plugin/plugin.json       # Plugin manifest
├── skills/
│   ├── flight-on/SKILL.md           # Activation protocol
│   └── flight-off/SKILL.md          # Deactivation protocol
├── hooks/hooks.json                 # Stop + PostToolUse hooks
├── scripts/
│   ├── stop-checkpoint.sh           # Auto-commit on session end
│   └── context-monitor.sh           # Context budget tracking
├── data/flight-profiles.md          # 40+ airline WiFi profiles
└── templates/claude-md-snippet.md   # CLAUDE.md addition
```

## Testing

```bash
# Unit tests (74 tests)
bash tests/run-tests.sh

# Full lifecycle simulation (22 tests)
bash tests/live-simulation.sh
```

## How the protocol layers work

| Layer | File | Purpose | When read |
|---|---|---|---|
| 1 | `/flight-on` SKILL.md | Full protocol (verbose) | Once, at activation |
| 2 | `FLIGHT_MODE.md` | Condensed protocol (~20 lines) | On recovery |
| 3 | `~/.claude/CLAUDE.md` snippet | "Read FLIGHT_MODE.md if it exists" | Every session start |
| 4 | Hooks | Auto-checkpoint + context monitor | Every tool call / session end |

Each layer does one job. No duplication. Hooks enforce mechanically; protocol text covers what hooks can't.

## License

MIT
