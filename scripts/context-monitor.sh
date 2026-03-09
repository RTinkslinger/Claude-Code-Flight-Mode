#!/bin/bash
# Flight Mode — PostToolUse hook: track context usage and inject warnings at thresholds
# Silent below 40% — zero context overhead for the first half of a session
# Uses /tmp state file keyed by project directory for cross-call persistence
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Use cwd from hook input, fall back to CLAUDE_PROJECT_DIR
WORKDIR="${CWD:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

# Only act if flight mode is active
[ -f "$WORKDIR/FLIGHT_MODE.md" ] || exit 0

# State file in /tmp keyed by project directory hash
# macOS uses md5, Linux uses md5sum
if command -v md5 >/dev/null 2>&1; then
  DIR_HASH=$(echo -n "$WORKDIR" | md5)
elif command -v md5sum >/dev/null 2>&1; then
  DIR_HASH=$(echo -n "$WORKDIR" | md5sum | cut -c1-12)
else
  DIR_HASH=$(echo -n "$WORKDIR" | cksum | cut -d' ' -f1)
fi

STATE_DIR="/tmp/flight-mode-${DIR_HASH}"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/context.json"

# Read tool name from hook input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Initialize or read state
if [ -f "$STATE_FILE" ]; then
  TOOL_CALLS=$(jq -r '.tool_calls // 0' "$STATE_FILE" 2>/dev/null || echo 0)
  FILE_READS=$(jq -r '.file_reads // 0' "$STATE_FILE" 2>/dev/null || echo 0)
  LINES_READ=$(jq -r '.lines_read // 0' "$STATE_FILE" 2>/dev/null || echo 0)
else
  TOOL_CALLS=0
  FILE_READS=0
  LINES_READ=0
fi

# Update counters
TOOL_CALLS=$((TOOL_CALLS + 1))

# Count file reads and estimate lines consumed
case "$TOOL_NAME" in
  Read|Grep|Glob)
    FILE_READS=$((FILE_READS + 1))
    # Estimate output size from tool_output length (rough proxy)
    OUTPUT_LINES=$(echo "$INPUT" | jq -r '.tool_output // ""' 2>/dev/null | wc -l | tr -d ' ')
    LINES_READ=$((LINES_READ + ${OUTPUT_LINES:-0}))
    ;;
esac

# Save state
cat > "$STATE_FILE" << EOF
{"tool_calls": $TOOL_CALLS, "file_reads": $FILE_READS, "lines_read": $LINES_READ}
EOF

# Calculate estimated context usage percentage
# Formula: (tool_calls * 2.5 + lines_read * 0.01) / 1.5
# 1.5 is a normalization factor that maps to ~100% at typical session limits
# Using awk for floating point math
ESTIMATED=$(echo "$TOOL_CALLS $LINES_READ" | awk '{
  raw = ($1 * 2.5 + $2 * 0.01) / 1.5
  printf "%.0f", raw
}')

# Inject warnings at thresholds — silent below 45%
if [ "$ESTIMATED" -ge 85 ] 2>/dev/null; then
  cat <<EOF
{"systemMessage": "FLIGHT MODE: ~${ESTIMATED}% context estimated (${TOOL_CALLS} tool calls, ${FILE_READS} file reads, ~${LINES_READ} lines). STOP. Write recovery instructions to .flight-state.md and suggest starting a new session."}
EOF
elif [ "$ESTIMATED" -ge 65 ] 2>/dev/null; then
  cat <<EOF
{"systemMessage": "FLIGHT MODE: ~${ESTIMATED}% context estimated (${TOOL_CALLS} tool calls, ${FILE_READS} file reads). Checkpoint NOW. Max 3 more micro-tasks remaining."}
EOF
elif [ "$ESTIMATED" -ge 45 ] 2>/dev/null; then
  cat <<EOF
{"systemMessage": "FLIGHT MODE: ~${ESTIMATED}% context estimated. Consider checkpointing soon."}
EOF
fi
# Below 45%: silent — zero context overhead

exit 0
