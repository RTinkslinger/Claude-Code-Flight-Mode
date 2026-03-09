#!/bin/bash
# Flight Mode — Stop hook: auto-checkpoint uncommitted changes on session end
# Only fires when FLIGHT_MODE.md exists (flight mode active)
# Uses --no-verify because this is an emergency checkpoint — pre-commit hooks
# should not prevent saving work when a session is ending on shaky WiFi
set -euo pipefail

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

# Check for uncommitted changes (works on repos with no commits too)
if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
  exit 0
fi

# Stage modified tracked files (not untracked — respect .gitignore)
git add -u 2>/dev/null || true

# Commit with auto-checkpoint message
git commit -m "flight: auto-checkpoint on session end" --no-verify 2>/dev/null || true

# Output JSON so Claude sees confirmation
cat <<EOF
{
  "decision": "approve",
  "reason": "Flight mode: auto-checkpointed uncommitted changes before session end.",
  "systemMessage": "Flight mode auto-checkpoint: committed uncommitted changes with 'flight: auto-checkpoint on session end'."
}
EOF

exit 0
