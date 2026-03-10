#!/bin/bash
# Flight Mode — Activation: writes FLIGHT_MODE.md + .flight-state.md
# Input: JSON on stdin with all flight data + cwd
# Output: JSON confirmation
set -uo pipefail

INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ]; then
  CWD="$(pwd)"
fi

AIRLINE_CODE=$(echo "$INPUT" | jq -r '.airline_code // "??"')
AIRLINE_NAME=$(echo "$INPUT" | jq -r '.airline_name // "Unknown"')
ORIGIN=$(echo "$INPUT" | jq -r '.origin // "???"')
DESTINATION=$(echo "$INPUT" | jq -r '.destination // "???"')
PROVIDER=$(echo "$INPUT" | jq -r '.provider // "unknown"')
RATING=$(echo "$INPUT" | jq -r '.rating // "USABLE"')
STABLE_WINDOW=$(echo "$INPUT" | jq -r '.stable_window // "20-40"')
DURATION=$(echo "$INPUT" | jq -r '.duration_hours // 5')
API_VERDICT=$(echo "$INPUT" | jq -r '.api_verdict // "UNKNOWN"')
EGRESS_COUNTRY=$(echo "$INPUT" | jq -r '.egress_country // "??"')
DASHBOARD_URL=$(echo "$INPUT" | jq -r '.dashboard_url // "http://localhost:8234"')
BATCH_SIZE=$(echo "$INPUT" | jq -r '.calibration.batch_size // "1-2"')
CHECKPOINT=$(echo "$INPUT" | jq -r '.calibration.checkpoint_interval // "2-3"')
COMMIT_INT=$(echo "$INPUT" | jq -r '.calibration.commit_interval // "2-3"')

WZ_START=$(echo "$INPUT" | jq -r '.weak_zone.start_hour // empty')
WZ_END=$(echo "$INPUT" | jq -r '.weak_zone.end_hour // empty')
WZ_REASON=$(echo "$INPUT" | jq -r '.weak_zone.reason // empty')

DATE_NOW=$(date +"%Y-%m-%d %H:%M")
PROJECT_NAME=$(basename "$CWD")

WEAK_ZONE_LINE=""
if [ -n "$WZ_START" ] && [ -n "$WZ_END" ]; then
  WEAK_ZONE_LINE="**Weak Zone:** Hours ${WZ_START}-${WZ_END} — ${WZ_REASON}"
fi

cat > "$CWD/FLIGHT_MODE.md" << FMEOF
# Flight Mode Active

**Airline:** ${AIRLINE_NAME} ${AIRLINE_CODE}
**Route:** ${ORIGIN} -> ${DESTINATION} (~${DURATION}h)
**WiFi:** ${PROVIDER} · Rating: ${RATING}
**API Status:** ${API_VERDICT} via ${EGRESS_COUNTRY}
**Activated:** ${DATE_NOW}
**Stable Window:** ${STABLE_WINDOW} min
**Dashboard:** ${DASHBOARD_URL}
${WEAK_ZONE_LINE:+
$WEAK_ZONE_LINE}

## Condensed Protocol (for session recovery)

1. **Read \`.flight-state.md\`** — resume from last incomplete micro-task
2. **Micro-tasks only** — max ${BATCH_SIZE} tool calls per task, decompose before starting
3. **Checkpoint every ${CHECKPOINT} tasks** — update \`.flight-state.md\` + git commit
4. **Git discipline** — \`flight:\` prefix, stage specific files (not \`git add -A\`), skip failed pre-commit hooks
5. **Context budget** — minimize file reads, read only what the current micro-task needs
6. **If a drop seems imminent** — finish current edit, commit immediately, update \`.flight-state.md\`
7. **Every edit must be self-contained** — never leave files in an inconsistent state
FMEOF

cat > "$CWD/.flight-state.md" << FSEOF
# Flight State

**Session started:** ${DATE_NOW}
**Airline:** ${AIRLINE_NAME} ${AIRLINE_CODE} ${ORIGIN}-${DESTINATION}
**WiFi:** ${PROVIDER} · Rating: ${RATING}
**API Status:** ${API_VERDICT}
**Project:** ${PROJECT_NAME}

## Current Task
(awaiting user input)

## Micro-Tasks
(not yet decomposed)

## Last Action
Flight mode activated. Awaiting task assignment.

## Files Modified This Session
(none yet)

## Recovery Instructions
If this session dropped: Flight mode is active but no task was assigned yet. Ask the user what they want to work on.
FSEOF

cat << OUTEOF
{
  "status": "activated",
  "flight_mode_path": "$CWD/FLIGHT_MODE.md",
  "flight_state_path": "$CWD/.flight-state.md"
}
OUTEOF
