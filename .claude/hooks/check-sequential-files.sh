#!/bin/bash
# Check if a file being edited is classified as Sequential.
# Outputs JSON with additionalContext so Claude actually sees the warning.
# Never blocks (no exit 2). Uses agent_type field (not agent_name — that doesn't exist).

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Only relevant for subagents — main session can edit anything
if [ -z "$AGENT_TYPE" ]; then
  exit 0
fi

# Check sequential files list using cwd from JSON (safer than CLAUDE_PROJECT_DIR env var)
SEQ_FILE="$CWD/.claude/sequential-files.txt"
if [ ! -f "$SEQ_FILE" ]; then
  exit 0  # No list = no restriction
fi

# Match against the list (exact whole-line match on basename to avoid false positives)
BASENAME=$(basename "$FILE_PATH" 2>/dev/null)
if [ -n "$BASENAME" ] && grep -qxF "$BASENAME" "$SEQ_FILE" 2>/dev/null; then
  # Use JSON additionalContext so Claude actually sees the warning (plain stderr is verbose-only)
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Allowed, but warning: $BASENAME is a Sequential file. Ensure no other agent is editing it simultaneously.",
    "additionalContext": "Warning: $BASENAME is listed in .claude/sequential-files.txt as a Sequential file. If other agents are running in parallel, coordinate to avoid merge conflicts."
  }
}
EOF
  exit 0
fi

exit 0
