#!/bin/bash
# Blocks direct Write to FLIGHT_MODE.md — forces use of flight-on-activate.sh
# PreToolUse hook for Write tool
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ "$(basename "$FILE_PATH")" = "FLIGHT_MODE.md" ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "FLIGHT_MODE.md must be created by flight-on-activate.sh, not written directly. Use the activate script."
  }
}
EOF
  exit 0
fi

exit 0
