#!/bin/bash
# Flight Mode — Stop hook: auto-checkpoint uncommitted changes on session end
# Only fires when FLIGHT_MODE.md exists (flight mode active)
# Uses --no-verify because this is an emergency checkpoint — pre-commit hooks
# should not prevent saving work when a session is ending on shaky WiFi
set -uo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Use cwd from hook input, fall back to CLAUDE_PROJECT_DIR
WORKDIR="${CWD:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
cd "$WORKDIR" 2>/dev/null || exit 0

# Only act if flight mode is active
[ -f "FLIGHT_MODE.md" ] || exit 0

# Break infinite loop: if stop hook already fired, let the session end
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

# Check for tracked file changes only (exclude untracked ?? lines)
# FLIGHT_MODE.md itself is typically untracked — don't trigger on that alone
TRACKED_CHANGES=$(git status --porcelain 2>/dev/null | grep -v '^??' | head -1 || true)
if [ -z "$TRACKED_CHANGES" ]; then
  exit 0
fi

# Stage modified tracked files (not untracked — respect .gitignore)
git add -u > /dev/null 2>&1 || true

# Commit with auto-checkpoint message (suppress all git output)
if git commit -m "flight: auto-checkpoint on session end" --no-verify > /dev/null 2>&1; then
  # Output JSON so Claude sees confirmation
  cat <<EOF
{
  "decision": "approve",
  "reason": "Flight mode: auto-checkpointed uncommitted changes before session end.",
  "systemMessage": "Flight mode auto-checkpoint: committed uncommitted changes with 'flight: auto-checkpoint on session end'."
}
EOF
fi

exit 0
