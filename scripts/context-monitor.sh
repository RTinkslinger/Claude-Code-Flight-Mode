#!/bin/bash
# Flight Mode — PostToolUse hook: track context usage and inject warnings at thresholds
# Silent below 40% — zero context overhead for the first half of a session
# Uses /tmp state file keyed by project directory for cross-call persistence
set -uo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Use cwd from hook input, fall back to CLAUDE_PROJECT_DIR
WORKDIR="${CWD:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

# Only act if flight mode is active
[ -f "$WORKDIR/FLIGHT_MODE.md" ] || exit 0

# State file in /tmp keyed by project directory hash
# macOS uses md5, Linux uses md5sum
if command -v md5 >/dev/null 2>&1; then
  DIR_HASH=$(echo -n "$WORKDIR" | md5 | cut -c1-12)
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
  TOOL_CALLS=$(jq -r '.tool_calls // 0' "$STATE_FILE" 2>/dev/null | grep -E '^[0-9]+$' || echo 0)
  FILE_READS=$(jq -r '.file_reads // 0' "$STATE_FILE" 2>/dev/null | grep -E '^[0-9]+$' || echo 0)
  LINES_READ=$(jq -r '.lines_read // 0' "$STATE_FILE" 2>/dev/null | grep -E '^[0-9]+$' || echo 0)
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

# Save state (atomic write via temp + mv)
cat > "${STATE_FILE}.tmp" << EOF
{"tool_calls": $TOOL_CALLS, "file_reads": $FILE_READS, "lines_read": $LINES_READ}
EOF
mv "${STATE_FILE}.tmp" "$STATE_FILE"

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

# --- Latency measurement & dashboard live-data (every 3rd tool call) ---
# Non-blocking: all network ops have timeouts and || true fallbacks
if [ $((TOOL_CALLS % 3)) -eq 0 ]; then
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  PING_MS=-1
  HTTP_MS=-1
  API_STATUS="OFFLINE"
  IS_DROP=false

  # Measure ping latency (timeout 2s — macOS uses ms, Linux uses s)
  if [[ "$(uname)" == "Darwin" ]]; then
    PING_OUT=$(ping -c 1 -W 2000 8.8.8.8 2>/dev/null) || true
  else
    PING_OUT=$(ping -c 1 -W 2 8.8.8.8 2>/dev/null) || true
  fi
  if [ -n "$PING_OUT" ]; then
    # Extract time from ping output (macOS: time=X.Y ms, Linux: time=X.Y ms)
    PING_MS=$(echo "$PING_OUT" | grep -oE 'time=[0-9]+\.?[0-9]*' | head -1 | cut -d= -f2 || echo "-1")
    PING_MS=${PING_MS:-"-1"}
  fi

  # Measure HTTP latency to Anthropic API (timeout 3s)
  HTTP_TIME=$(curl -o /dev/null -s -w '%{time_total}' --max-time 3 https://api.anthropic.com 2>/dev/null) || true
  if [ -n "$HTTP_TIME" ] && [ "$HTTP_TIME" != "0.000000" ]; then
    # Convert seconds to milliseconds
    HTTP_MS=$(echo "$HTTP_TIME" | awk '{printf "%.0f", $1 * 1000}' 2>/dev/null || echo "-1")
    HTTP_MS=${HTTP_MS:-"-1"}
  fi

  # Determine API status based on measurements
  if [ "$PING_MS" = "-1" ] && [ "$HTTP_MS" = "-1" ]; then
    API_STATUS="OFFLINE"
    IS_DROP=true
  elif [ "$HTTP_MS" != "-1" ] && [ "$HTTP_MS" -gt 5000 ] 2>/dev/null; then
    API_STATUS="BLOCKED"
    IS_DROP=true
  elif [ "$HTTP_MS" != "-1" ] && [ "$HTTP_MS" -gt 2000 ] 2>/dev/null; then
    API_STATUS="CAUTION"
  elif [ "$HTTP_MS" != "-1" ]; then
    API_STATUS="GO"
  elif [ "$PING_MS" != "-1" ]; then
    API_STATUS="CAUTION"
  fi

  # Drop detection: ping failed or latency > 5000ms
  if [ "$PING_MS" != "-1" ]; then
    PING_INT=$(echo "$PING_MS" | awk '{printf "%.0f", $1}' 2>/dev/null || echo "0")
    if [ "${PING_INT:-0}" -gt 5000 ] 2>/dev/null; then
      IS_DROP=true
    fi
  fi

  # Read existing measurements and drops from state file
  MEASUREMENTS=$(jq -c '.measurements // []' "$STATE_FILE" 2>/dev/null || echo "[]")
  DROPS=$(jq -c '.drops // []' "$STATE_FILE" 2>/dev/null || echo "[]")

  # Append new measurement (keep last 20)
  NEW_MEASUREMENT="{\"timestamp\": \"${TIMESTAMP}\", \"ping_ms\": ${PING_MS}, \"http_ms\": ${HTTP_MS}}"
  MEASUREMENTS=$(echo "$MEASUREMENTS" | jq -c ". + [${NEW_MEASUREMENT}] | .[-20:]" 2>/dev/null || echo "[${NEW_MEASUREMENT}]")

  # Append drop event if detected (keep last 10)
  if [ "$IS_DROP" = true ]; then
    PEAK_LATENCY=${HTTP_MS}
    [ "$PEAK_LATENCY" = "-1" ] && PEAK_LATENCY=${PING_MS}
    [ "$PEAK_LATENCY" = "-1" ] && PEAK_LATENCY=0
    PACKET_LOSS=0
    [ "$PING_MS" = "-1" ] && PACKET_LOSS=100
    NEW_DROP="{\"timestamp\": \"${TIMESTAMP}\", \"duration_s\": 0, \"peak_latency_ms\": ${PEAK_LATENCY}, \"packet_loss\": ${PACKET_LOSS}}"
    DROPS=$(echo "$DROPS" | jq -c ". + [${NEW_DROP}] | .[-10:]" 2>/dev/null || echo "[${NEW_DROP}]")
  fi

  # Update state file with measurements and drops
  UPDATED_STATE=$(jq -c --argjson m "$MEASUREMENTS" --argjson d "$DROPS" \
    '. + {measurements: $m, drops: $d}' "$STATE_FILE" 2>/dev/null) || true
  if [ -n "$UPDATED_STATE" ]; then
    echo "$UPDATED_STATE" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
  fi

  # Write live-data.json to dashboard serve directory if it exists
  DASHBOARD_DIR="/tmp/flight-mode-dashboard-${DIR_HASH}"
  if [ -d "$DASHBOARD_DIR" ]; then
    LIVE_DATA=$(cat <<LIVEEOF
{
  "api_status": "${API_STATUS}",
  "egress_country": "",
  "egress_city": "",
  "measurements": ${MEASUREMENTS},
  "drops": ${DROPS},
  "session": {
    "tool_calls": ${TOOL_CALLS},
    "file_reads": ${FILE_READS},
    "context_pct": ${ESTIMATED}
  }
}
LIVEEOF
)
    echo "$LIVE_DATA" | jq -c '.' > "${DASHBOARD_DIR}/live-data.json" 2>/dev/null || true
  fi
fi
# --- End latency measurement ---

exit 0
