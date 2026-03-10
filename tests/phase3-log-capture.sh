#!/bin/bash
# Phase 3 Live Test — Log Capture
# Runs in background, polls filesystem + dashboard + git state every 2 seconds
# Writes timestamped log to /tmp/flight-test-log.txt
# Usage: bash tests/phase3-log-capture.sh &
# Stop:  touch /tmp/flight-test-stop

set -u

TEST_REPO="/tmp/flight-test-repo"
LOG_FILE="/tmp/flight-test-log.txt"
STOP_FILE="/tmp/flight-test-stop"
POLL_INTERVAL=2
DASHBOARD_PORT=8234

# Clean up from previous runs
rm -f "$LOG_FILE" "$STOP_FILE"

log() {
  local ts
  ts=$(date "+%H:%M:%S")
  echo "[$ts] $1" >> "$LOG_FILE"
  echo "[$ts] $1"
}

log "=========================================="
log "Phase 3 Log Capture Started"
log "Monitoring: $TEST_REPO"
log "Dashboard:  http://localhost:$DASHBOARD_PORT"
log "Stop with:  touch $STOP_FILE"
log "=========================================="

PREV_FM="none"
PREV_FS="none"
PREV_GI="none"
PREV_DASH="unknown"
PREV_COMMITS=0
PREV_FILES=""

while [ ! -f "$STOP_FILE" ]; do
  CHANGES=""

  # --- 1. FLIGHT_MODE.md ---
  if [ -f "$TEST_REPO/FLIGHT_MODE.md" ]; then
    FM_STATE="exists ($(wc -l < "$TEST_REPO/FLIGHT_MODE.md" | tr -d ' ') lines)"
  else
    FM_STATE="absent"
  fi
  if [ "$FM_STATE" != "$PREV_FM" ]; then
    log "FLIGHT_MODE.md: $PREV_FM -> $FM_STATE"
    if [ "$FM_STATE" != "absent" ]; then
      # Log first 5 lines of content
      log "  Content preview:"
      head -5 "$TEST_REPO/FLIGHT_MODE.md" 2>/dev/null | while IFS= read -r line; do
        log "    $line"
      done
    fi
    PREV_FM="$FM_STATE"
    CHANGES="yes"
  fi

  # --- 2. .flight-state.md ---
  if [ -f "$TEST_REPO/.flight-state.md" ]; then
    FS_STATE="exists ($(wc -l < "$TEST_REPO/.flight-state.md" | tr -d ' ') lines)"
  else
    FS_STATE="absent"
  fi
  if [ "$FS_STATE" != "$PREV_FS" ]; then
    log ".flight-state.md: $PREV_FS -> $FS_STATE"
    PREV_FS="$FS_STATE"
    CHANGES="yes"
  fi

  # --- 3. .gitignore ---
  if [ -f "$TEST_REPO/.gitignore" ]; then
    GI_STATE="exists ($(wc -l < "$TEST_REPO/.gitignore" | tr -d ' ') lines)"
  else
    GI_STATE="absent"
  fi
  if [ "$GI_STATE" != "$PREV_GI" ]; then
    log ".gitignore: $PREV_GI -> $GI_STATE"
    if [ "$GI_STATE" != "absent" ]; then
      log "  Content:"
      cat "$TEST_REPO/.gitignore" 2>/dev/null | while IFS= read -r line; do
        log "    $line"
      done
    fi
    PREV_GI="$GI_STATE"
    CHANGES="yes"
  fi

  # --- 4. Dashboard status ---
  DASH_HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "http://localhost:$DASHBOARD_PORT/" 2>/dev/null || echo "000")
  if [ "$DASH_HTTP" = "200" ]; then
    DASH_STATE="UP (HTTP 200)"
  else
    DASH_STATE="DOWN (HTTP $DASH_HTTP)"
  fi
  if [ "$DASH_STATE" != "$PREV_DASH" ]; then
    log "Dashboard: $PREV_DASH -> $DASH_STATE"
    PREV_DASH="$DASH_STATE"
    CHANGES="yes"
  fi

  # --- 5. Git commits ---
  if [ -d "$TEST_REPO/.git" ]; then
    COMMIT_COUNT=$(cd "$TEST_REPO" && git log --oneline 2>/dev/null | wc -l | tr -d ' ')
    FLIGHT_COMMITS=$(cd "$TEST_REPO" && git log --oneline 2>/dev/null | grep "flight:" | wc -l | tr -d ' ')
    if [ "$COMMIT_COUNT" != "$PREV_COMMITS" ]; then
      log "Git: $PREV_COMMITS -> $COMMIT_COUNT commits ($FLIGHT_COMMITS with flight: prefix)"
      LATEST=$(cd "$TEST_REPO" && git log --oneline -1 2>/dev/null)
      log "  Latest: $LATEST"
      PREV_COMMITS="$COMMIT_COUNT"
      CHANGES="yes"
    fi
  fi

  # --- 6. New files in test repo ---
  if [ -d "$TEST_REPO" ]; then
    CURRENT_FILES=$(ls -1A "$TEST_REPO" 2>/dev/null | grep -v '^\.git$' | sort | tr '\n' '|')
    if [ "$CURRENT_FILES" != "$PREV_FILES" ]; then
      log "Files in repo changed: $(echo "$CURRENT_FILES" | tr '|' ' ')"
      PREV_FILES="$CURRENT_FILES"
      CHANGES="yes"
    fi
  fi

  # --- 7. Dashboard data files ---
  DASH_DIR=$(ls -d /tmp/flight-mode-dashboard-* 2>/dev/null | head -1)
  if [ -n "$DASH_DIR" ] && [ -d "$DASH_DIR" ]; then
    ROUTE_DATA="$DASH_DIR/route-data.json"
    if [ -f "$ROUTE_DATA" ]; then
      ROUTE_SIZE=$(wc -c < "$ROUTE_DATA" | tr -d ' ')
      ROUTE_HASH=$(md5 -q "$ROUTE_DATA" 2>/dev/null || md5sum "$ROUTE_DATA" 2>/dev/null | cut -c1-8 || echo "?")
      if [ "${PREV_ROUTE_HASH:-}" != "$ROUTE_HASH" ]; then
        if [ "$ROUTE_SIZE" -gt 5 ]; then
          ROUTE_FLIGHT=$(jq -r '.flight // .flight_code // "?"' "$ROUTE_DATA" 2>/dev/null)
          ROUTE_ROUTE=$(jq -r '.route // "?"' "$ROUTE_DATA" 2>/dev/null)
          ROUTE_RATING=$(jq -r '.rating // "?"' "$ROUTE_DATA" 2>/dev/null)
          ROUTE_WP_COUNT=$(jq '.waypoints | length' "$ROUTE_DATA" 2>/dev/null || echo "0")
          ROUTE_WZ=$(jq -r 'if .weak_zone then "hours \(.weak_zone.start_hour)-\(.weak_zone.end_hour)" else "none" end' "$ROUTE_DATA" 2>/dev/null || echo "?")
          log "Dashboard route-data.json UPDATED (${ROUTE_SIZE}B):"
          log "  flight=$ROUTE_FLIGHT route=$ROUTE_ROUTE rating=$ROUTE_RATING"
          log "  waypoints=$ROUTE_WP_COUNT weak_zone=$ROUTE_WZ"
        else
          log "Dashboard route-data.json: empty (${ROUTE_SIZE}B)"
        fi
        PREV_ROUTE_HASH="$ROUTE_HASH"
        CHANGES="yes"
      fi
    fi

    # Check live-data.json changes
    LIVE_DATA="$DASH_DIR/live-data.json"
    if [ -f "$LIVE_DATA" ]; then
      LIVE_SIZE=$(wc -c < "$LIVE_DATA" | tr -d ' ')
      LIVE_HASH=$(md5 -q "$LIVE_DATA" 2>/dev/null || md5sum "$LIVE_DATA" 2>/dev/null | cut -c1-8 || echo "?")
      if [ "${PREV_LIVE_HASH:-}" != "$LIVE_HASH" ] && [ "$LIVE_SIZE" -gt 5 ]; then
        log "Dashboard live-data.json UPDATED (${LIVE_SIZE}B)"
        PREV_LIVE_HASH="$LIVE_HASH"
        CHANGES="yes"
      fi
    fi
  fi

  # --- 8. Archived flight state ---
  ARCHIVED=$(ls "$TEST_REPO"/.flight-state-*.md 2>/dev/null | head -1)
  if [ -n "$ARCHIVED" ] && [ ! -f "$TEST_REPO/.flight-state.md" ]; then
    log "Flight state archived: $(basename "$ARCHIVED")"
  fi

  sleep "$POLL_INTERVAL"
done

log "=========================================="
log "Phase 3 Log Capture Stopped"
log "=========================================="

# Final state snapshot
log ""
log "=== FINAL STATE ==="
log "FLIGHT_MODE.md: $([ -f "$TEST_REPO/FLIGHT_MODE.md" ] && echo "EXISTS" || echo "ABSENT")"
log ".flight-state.md: $([ -f "$TEST_REPO/.flight-state.md" ] && echo "EXISTS" || echo "ABSENT")"
log "Archived states: $(ls "$TEST_REPO"/.flight-state-*.md 2>/dev/null | xargs -I{} basename {} | tr '\n' ' ')"

FINAL_DASH_HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "http://localhost:$DASHBOARD_PORT/" 2>/dev/null || echo "000")
log "Dashboard HTTP: $FINAL_DASH_HTTP"

FINAL_DASH_DIR=$(ls -d /tmp/flight-mode-dashboard-* 2>/dev/null | head -1)
if [ -n "$FINAL_DASH_DIR" ] && [ -d "$FINAL_DASH_DIR" ]; then
  log "Dashboard dir: $FINAL_DASH_DIR"
  log "Dashboard files: $(ls -1 "$FINAL_DASH_DIR" 2>/dev/null | tr '\n' ' ')"
  if [ -f "$FINAL_DASH_DIR/route-data.json" ]; then
    log "route-data.json snapshot:"
    jq -c '{flight: (.flight // .flight_code), route, airline: (.airline // .airline_name), rating, duration_hours, weak_zone, waypoints_count: (.waypoints | length)}' "$FINAL_DASH_DIR/route-data.json" 2>/dev/null | while IFS= read -r line; do
      log "  $line"
    done
  fi
  if [ -f "$FINAL_DASH_DIR/server.pid" ]; then
    DASH_PID=$(cat "$FINAL_DASH_DIR/server.pid" 2>/dev/null)
    if kill -0 "$DASH_PID" 2>/dev/null; then
      log "Dashboard server PID $DASH_PID: ALIVE"
    else
      log "Dashboard server PID $DASH_PID: DEAD"
    fi
  fi
else
  log "Dashboard dir: NOT FOUND"
fi

log "Git commits:"
(cd "$TEST_REPO" 2>/dev/null && git log --oneline 2>/dev/null | while IFS= read -r line; do
  log "  $line"
done)
log "Files: $(ls -1A "$TEST_REPO" 2>/dev/null | grep -v '^\.git$' | tr '\n' ' ')"
log "=== END ==="

rm -f "$STOP_FILE"
echo ""
echo "Log saved to: $LOG_FILE"
