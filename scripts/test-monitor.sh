#!/bin/bash
# Flight Mode Test Monitor
# Watches for dashboard creation, file changes, and server status
# Usage: bash scripts/test-monitor.sh [target-repo-path]
# Runs continuously — Ctrl+C to stop

set -uo pipefail

TARGET_REPO="${1:-}"
POLL_INTERVAL=3

# Colors
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

log() { echo -e "${DIM}$(date '+%H:%M:%S')${RESET} $1"; }
ok()  { log "${GREEN}[OK]${RESET} $1"; }
warn(){ log "${YELLOW}[WARN]${RESET} $1"; }
err() { log "${RED}[ERR]${RESET} $1"; }
info(){ log "${CYAN}[INFO]${RESET} $1"; }

echo -e "\n${BOLD}${CYAN}=== Flight Mode Test Monitor ===${RESET}"
echo -e "${DIM}Polling every ${POLL_INTERVAL}s — Ctrl+C to stop${RESET}\n"

# Track state changes
PREV_DASHBOARD_DIR=""
PREV_SERVER_PID=""
PREV_ROUTE_DATA=""
PREV_LIVE_DATA=""
PREV_FLIGHT_MODE=""
PREV_FLIGHT_STATE=""
ITERATION=0

while true; do
  ITERATION=$((ITERATION + 1))
  CHANGES=0

  # --- 1. Find dashboard directories ---
  DASHBOARD_DIRS=$(ls -d /tmp/flight-mode-dashboard-* 2>/dev/null || true)

  if [ -n "$DASHBOARD_DIRS" ]; then
    for dir in $DASHBOARD_DIRS; do
      if [ "$dir" != "$PREV_DASHBOARD_DIR" ]; then
        ok "Dashboard directory created: ${BOLD}$dir${RESET}"
        PREV_DASHBOARD_DIR="$dir"
        CHANGES=1

        # Check contents
        if [ -f "$dir/index.html" ]; then
          LINES=$(wc -l < "$dir/index.html" | tr -d ' ')
          ok "  index.html exists ($LINES lines)"
        else
          err "  index.html MISSING"
        fi
      fi

      # Check server PID
      if [ -f "$dir/server.pid" ]; then
        PID=$(cat "$dir/server.pid" 2>/dev/null)
        if [ "$PID" != "$PREV_SERVER_PID" ]; then
          if kill -0 "$PID" 2>/dev/null; then
            ok "Dashboard server running: PID $PID"
            # Check port
            if lsof -i :8234 -P -n 2>/dev/null | grep -q LISTEN; then
              ok "  Port 8234 is LISTENING"
            else
              warn "  Port 8234 not detected in lsof"
            fi
          else
            err "Dashboard server PID $PID is NOT running"
          fi
          PREV_SERVER_PID="$PID"
          CHANGES=1
        fi
      fi

      # Check route-data.json changes
      if [ -f "$dir/route-data.json" ]; then
        ROUTE_HASH=$(md5 -q "$dir/route-data.json" 2>/dev/null || md5sum "$dir/route-data.json" 2>/dev/null | cut -c1-12)
        if [ "$ROUTE_HASH" != "$PREV_ROUTE_DATA" ]; then
          ROUTE_SIZE=$(wc -c < "$dir/route-data.json" | tr -d ' ')
          if [ "$ROUTE_SIZE" -gt 5 ]; then
            ok "route-data.json updated (${ROUTE_SIZE} bytes)"
            # Show key fields
            FLIGHT=$(jq -r '.flight // .flight_code // "?"' "$dir/route-data.json" 2>/dev/null)
            ROUTE=$(jq -r '.route // "?"' "$dir/route-data.json" 2>/dev/null)
            RATING=$(jq -r '.rating // "?"' "$dir/route-data.json" 2>/dev/null)
            DURATION=$(jq -r '.duration_hours // "?"' "$dir/route-data.json" 2>/dev/null)
            WP_COUNT=$(jq '.waypoints | length' "$dir/route-data.json" 2>/dev/null || echo "0")
            info "  Flight: $FLIGHT | Route: $ROUTE | Rating: $RATING | Duration: ${DURATION}h | Waypoints: $WP_COUNT"
          else
            info "route-data.json is empty/minimal (${ROUTE_SIZE} bytes)"
          fi
          PREV_ROUTE_DATA="$ROUTE_HASH"
          CHANGES=1
        fi
      fi

      # Check live-data.json changes
      if [ -f "$dir/live-data.json" ]; then
        LIVE_HASH=$(md5 -q "$dir/live-data.json" 2>/dev/null || md5sum "$dir/live-data.json" 2>/dev/null | cut -c1-12)
        if [ "$LIVE_HASH" != "$PREV_LIVE_DATA" ]; then
          LIVE_SIZE=$(wc -c < "$dir/live-data.json" | tr -d ' ')
          if [ "$LIVE_SIZE" -gt 5 ]; then
            ok "live-data.json updated (${LIVE_SIZE} bytes)"
            API_STATUS=$(jq -r '.api_status // "?"' "$dir/live-data.json" 2>/dev/null)
            MEAS_COUNT=$(jq '.measurements | length' "$dir/live-data.json" 2>/dev/null || echo "0")
            DROP_COUNT=$(jq '.drops | length' "$dir/live-data.json" 2>/dev/null || echo "0")
            CTX_PCT=$(jq -r '.session.context_pct // "?"' "$dir/live-data.json" 2>/dev/null)
            info "  API: $API_STATUS | Measurements: $MEAS_COUNT | Drops: $DROP_COUNT | Context: ${CTX_PCT}%"
          fi
          PREV_LIVE_DATA="$LIVE_HASH"
          CHANGES=1
        fi
      fi
    done
  fi

  # --- 2. Check context monitor state files ---
  CONTEXT_DIRS=$(ls -d /tmp/flight-mode-[!d]* 2>/dev/null || true)
  for cdir in $CONTEXT_DIRS; do
    if [ -f "$cdir/context.json" ]; then
      TC=$(jq -r '.tool_calls // 0' "$cdir/context.json" 2>/dev/null || echo 0)
      FR=$(jq -r '.file_reads // 0' "$cdir/context.json" 2>/dev/null || echo 0)
      if [ "$ITERATION" -eq 1 ] || [ $((ITERATION % 10)) -eq 0 ]; then
        info "Context state ($cdir): tool_calls=$TC, file_reads=$FR"
      fi
    fi
  done

  # --- 3. Check target repo for FLIGHT_MODE.md / .flight-state.md ---
  if [ -n "$TARGET_REPO" ]; then
    if [ -f "$TARGET_REPO/FLIGHT_MODE.md" ]; then
      if [ "$PREV_FLIGHT_MODE" != "exists" ]; then
        err "FLIGHT_MODE.md EXISTS in $TARGET_REPO (should NOT exist for this test!)"
        PREV_FLIGHT_MODE="exists"
        CHANGES=1
      fi
    else
      if [ "$PREV_FLIGHT_MODE" = "exists" ]; then
        ok "FLIGHT_MODE.md removed from $TARGET_REPO"
        PREV_FLIGHT_MODE=""
        CHANGES=1
      fi
    fi

    if [ -f "$TARGET_REPO/.flight-state.md" ]; then
      if [ "$PREV_FLIGHT_STATE" != "exists" ]; then
        err ".flight-state.md EXISTS in $TARGET_REPO (should NOT exist for this test!)"
        PREV_FLIGHT_STATE="exists"
        CHANGES=1
      fi
    else
      if [ "$PREV_FLIGHT_STATE" = "exists" ]; then
        ok ".flight-state.md removed from $TARGET_REPO"
        PREV_FLIGHT_STATE=""
        CHANGES=1
      fi
    fi
  fi

  # --- 4. Check HTTP response from dashboard ---
  if [ -n "$PREV_SERVER_PID" ] && kill -0 "$PREV_SERVER_PID" 2>/dev/null; then
    if [ $((ITERATION % 5)) -eq 0 ]; then
      HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://localhost:8234/ 2>/dev/null || echo "000")
      if [ "$HTTP_CODE" = "200" ]; then
        ok "Dashboard HTTP 200 OK"
      else
        warn "Dashboard HTTP $HTTP_CODE"
      fi
    fi
  fi

  # Separator on changes
  if [ "$CHANGES" -gt 0 ]; then
    echo -e "${DIM}---${RESET}"
  fi

  sleep "$POLL_INTERVAL"
done
