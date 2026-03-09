# Claude Code Plugin Development — Local Reference

> **Purpose:** Quick reference for building the Flight Mode plugin. Compiled from official Claude Code docs, plugin-dev skills, and hooks documentation.
> **Last updated:** 2026-03-09

---

## Plugin Directory Structure

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json              # Manifest (MUST be here)
├── commands/                    # Legacy command location (auto-discovered)
├── agents/                      # Subagent definitions (auto-discovered)
├── skills/                      # Skills with SKILL.md (auto-discovered)
│   └── skill-name/
│       ├── SKILL.md             # Required entry point
│       ├── references/          # Optional supporting docs
│       └── scripts/             # Optional helper scripts
├── hooks/
│   └── hooks.json               # Hook configuration
├── scripts/                     # Hook and utility scripts
├── .mcp.json                    # MCP server definitions (optional)
├── settings.json                # Default plugin settings (optional)
└── LICENSE
```

**Critical:** Only `plugin.json` goes in `.claude-plugin/`. Everything else at plugin root.

---

## plugin.json Schema

```json
{
  "name": "kebab-case-name",         // REQUIRED. Regex: /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/
  "version": "1.0.0",               // Semantic versioning
  "description": "50-200 chars",     // What plugin does
  "author": {
    "name": "Name",
    "email": "email@example.com",
    "url": "https://..."
  },
  "homepage": "https://docs-url",
  "repository": "https://github-url",
  "license": "MIT",
  "keywords": ["tag1", "tag2"],
  "commands": "./commands",          // String or array, supplements default
  "agents": "./agents",             // String or array
  "skills": "./skills",             // String or array
  "hooks": "./hooks/hooks.json",    // String path or inline object
  "mcpServers": "./.mcp.json"       // String path or inline object
}
```

**Path rules:** Must be relative, start with `./`, no `../`, forward slashes only.

---

## Skills (SKILL.md)

### Frontmatter Fields

```yaml
---
name: skill-name                     # lowercase-hyphens, max 64 chars
description: When Claude should use  # Drives auto-invocation
argument-hint: [optional-args]       # Autocomplete hint
disable-model-invocation: false      # Block auto-invocation
user-invocable: true                 # Show in / menu
allowed-tools: Read, Grep, Bash      # Auto-allowed tools (no permission prompt)
model: sonnet                        # sonnet, opus, haiku, inherit
context: fork                        # fork = isolated subagent context
agent: Explore                       # Subagent type when context: fork
---
```

### String Substitutions

| Variable | Description |
|---|---|
| `$ARGUMENTS` | All passed arguments |
| `$ARGUMENTS[N]` or `$N` | Nth argument (0-indexed) |
| `${CLAUDE_SESSION_ID}` | Current session ID |
| `${CLAUDE_SKILL_DIR}` | Directory containing SKILL.md |
| `${CLAUDE_PLUGIN_ROOT}` | Plugin root directory |

### Command Injection

`` !`command` `` — runs shell command, output replaces placeholder before Claude sees it.

```markdown
Current git status: !`git status --short`
```

### Invocation Control

| Frontmatter | User can invoke | Claude can invoke |
|---|---|---|
| (default) | YES | YES |
| `disable-model-invocation: true` | YES | NO |
| `user-invocable: false` | NO | YES |

---

## Hooks

### hooks.json Format (Plugin)

```json
{
  "description": "Optional description",
  "hooks": {
    "EventName": [
      {
        "matcher": "ToolName|Pattern",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hook.sh",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

**Key:** Plugin hooks use `{"description": ..., "hooks": {...}}` wrapper. Settings hooks use direct event format.

### Hook Types

| Type | Use For | Example |
|---|---|---|
| `command` | Deterministic checks, file ops, external tools | `"command": "bash script.sh"` |
| `prompt` | Context-aware LLM decisions | `"prompt": "Is this safe?"` |
| `agent` | Multi-turn verification with tool access | `"prompt": "Verify this..."` |
| `http` | External service integration | `"url": "http://localhost:8080"` |

### Hook Events

| Event | Matcher Filters | Key Input Fields | Key Output |
|---|---|---|---|
| **SessionStart** | `startup\|resume\|clear\|compact` | `start_method`, `cwd` | stdout → Claude context |
| **UserPromptSubmit** | none (always fires) | `user_prompt` | stdout → Claude context |
| **PreToolUse** | tool names (`Bash\|Edit`) | `tool_name`, `tool_input` | `permissionDecision: allow\|deny\|ask` |
| **PostToolUse** | tool names | `tool_name`, `tool_input`, `tool_output` | `systemMessage` for Claude |
| **PostToolUseFailure** | tool names | `tool_name`, `tool_input`, `tool_error` | same as PostToolUse |
| **PermissionRequest** | tool names | `tool_name`, `tool_input` | `permissionDecision: allow\|deny` |
| **Stop** | none (always fires) | `reason` | `decision: approve\|block` |
| **SubagentStop** | agent type names | `agent_type`, `agent_id` | same as Stop |
| **SessionEnd** | `clear\|logout\|other` | `session_id` | cleanup |
| **PreCompact** | `manual\|auto` | — | preserve context |
| **Notification** | `permission_prompt\|idle_prompt` | `notification_type`, `message` | logging only |

### Exit Codes

| Code | Meaning | Behavior |
|---|---|---|
| `0` | Success | stdout parsed as JSON. For SessionStart/UserPromptSubmit: added to Claude context. For others: verbose only. |
| `1` | Non-blocking error | stderr in verbose mode. Execution continues. |
| `2` | Blocking error | stderr fed to Claude. For PreToolUse: tool blocked. For Stop: Claude CONTINUES (counterintuitive). |

### JSON Output Schema

**PreToolUse:**
```json
{
  "hookSpecificOutput": {
    "permissionDecision": "allow|deny|ask",
    "updatedInput": {"field": "modified_value"}
  },
  "systemMessage": "Context for Claude"
}
```

**Stop:**
```json
{
  "decision": "approve|block",
  "reason": "Why",
  "systemMessage": "Additional context"
}
```

**PostToolUse:**
```json
{
  "systemMessage": "Feedback for Claude"
}
```

**Universal fields (any hook):**
```json
{
  "continue": true,
  "suppressOutput": false,
  "systemMessage": "Message for Claude"
}
```

### Hook Input JSON (stdin)

All hooks receive:
```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/path/to/working/dir",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {"command": "npm test"},
  "tool_output": "result..."
}
```

### Environment Variables in Hooks

| Variable | Available In | Description |
|---|---|---|
| `$CLAUDE_PROJECT_DIR` | All command hooks | Project root path |
| `$CLAUDE_PLUGIN_ROOT` | Plugin hooks only | Plugin directory (portable paths) |
| `$CLAUDE_ENV_FILE` | SessionStart only | Write env vars to persist |

### Matcher Patterns

```json
"matcher": "Bash"                    // Exact match
"matcher": "Read|Write|Edit"         // Multiple tools
"matcher": "*"                       // All (or ".*" for regex)
"matcher": "mcp__.*__delete.*"       // MCP tool regex
```

Case-sensitive. Uses regex syntax.

### Key Gotchas

1. **Hooks snapshot at startup** — file edits need session restart to take effect
2. **Shell profile `echo` breaks JSON parsing** — wrap in `if [[ $- == *i* ]]`
3. **Stop hook exit 2 = keep working** (counterintuitive — "block" means block the stop)
4. **`stop_hook_active` field** — use for loop prevention in Stop hooks
5. **PermissionRequest doesn't fire in headless mode** (`-p` flag)
6. **Hooks within a matcher run in parallel** — design for independence
7. **`--no-verify` in stop hook** is acceptable since it's an emergency checkpoint

### Flag-File Activation Pattern

For hooks that should only fire conditionally:
```bash
#!/bin/bash
# Only active when flight mode is on
[ -f "FLIGHT_MODE.md" ] || exit 0

# ... hook logic ...
```

---

## Agents (Subagent Definitions)

### Frontmatter

```yaml
---
name: agent-name
description: When Claude should delegate to this agent
tools: Read, Grep, Glob, Bash       # Or Agent(worker) for sub-spawning
disallowedTools: Write, Edit
model: sonnet                        # sonnet, opus, haiku, inherit
maxTurns: 10
---
```

Not needed for Flight Mode V1 — no custom agents required.

---

## Plugin Installation

```bash
# Global install (all repos)
claude plugin install <path-or-url> --scope user

# Development testing
claude --plugin-dir ./my-plugin

# Debug mode (shows plugin loading, hook execution)
claude --debug

# List loaded agents
claude agents

# Review loaded hooks in session
/hooks
```

---

## Command Hooks for Flight Mode

### stop-checkpoint.sh Pattern

```bash
#!/bin/bash
set -euo pipefail
[ -f "FLIGHT_MODE.md" ] || exit 0  # No-op if not in flight mode

# Check for uncommitted changes
if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
  exit 0
fi

# Auto-checkpoint
git add -u 2>/dev/null || true
git commit -m "flight: auto-checkpoint on session end" --no-verify 2>/dev/null || true
echo '{"systemMessage": "Flight mode: auto-checkpointed uncommitted changes."}'
exit 0
```

### context-monitor.sh Pattern

```bash
#!/bin/bash
set -euo pipefail
[ -f "FLIGHT_MODE.md" ] || exit 0  # No-op if not in flight mode

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // ""')

# Maintain state in /tmp
STATE_FILE="/tmp/flight-ctx-$(echo "$PWD" | md5 -q -s "$PWD" 2>/dev/null || echo "$PWD" | md5sum | cut -c1-12).json"

# Read/update counters...
# Calculate estimated usage...
# Output systemMessage at thresholds...
exit 0
```

---

## Testing Hooks

```bash
# Test a command hook with sample input
echo '{"tool_name": "Write", "tool_input": {"file_path": "test.js"}}' | \
  bash scripts/stop-checkpoint.sh
echo "Exit code: $?"

# Validate hooks.json syntax
jq . hooks/hooks.json

# Test plugin loading
claude --debug --plugin-dir .
```

---

## Quick Reference: Flight Mode Plugin Components

| Component | Type | File | Purpose |
|---|---|---|---|
| `/flight-on` | Skill | `skills/flight-on/SKILL.md` | Activate flight mode |
| `/flight-off` | Skill | `skills/flight-off/SKILL.md` | Deactivate + summarize |
| Stop checkpoint | Hook (command) | `scripts/stop-checkpoint.sh` | Auto-commit on session end |
| Context monitor | Hook (command) | `scripts/context-monitor.sh` | Track + warn on context budget |
| WiFi profiles | Data | `data/flight-profiles.md` | Airline lookup table |
| CLAUDE.md snippet | Template | `templates/claude-md-snippet.md` | User's one-time setup |
