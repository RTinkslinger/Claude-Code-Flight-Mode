#!/bin/bash
# Flight Mode — Dashboard HTTP server manager
# Manages a Python HTTP server for the Flight Mode dashboard
# Commands: start, stop, status, write-route, write-live
set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
PLUGIN_DIR=$(echo "$INPUT" | jq -r '.plugin_dir // empty')
PORT=$(echo "$INPUT" | jq -r '.port // empty')

# Resolve plugin directory: input > env var > script's parent directory
if [ -z "$PLUGIN_DIR" ]; then
  PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
fi

# Resolve working directory for hash computation
WORKDIR="${CWD:-$(pwd)}"

# Default port
PORT="${PORT:-8234}"

# Compute directory hash (same approach as context-monitor.sh)
if command -v md5 >/dev/null 2>&1; then
  DIR_HASH=$(echo -n "$WORKDIR" | md5 | cut -c1-12)
elif command -v md5sum >/dev/null 2>&1; then
  DIR_HASH=$(echo -n "$WORKDIR" | md5sum | cut -c1-12)
else
  DIR_HASH=$(echo -n "$WORKDIR" | cksum | cut -d' ' -f1)
fi

SERVE_DIR="/tmp/flight-mode-dashboard-${DIR_HASH}"
PID_FILE="${SERVE_DIR}/server.pid"

# Check if server process is alive
is_running() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "$pid"
      return 0
    fi
  fi
  return 1
}

cmd_start() {
  # Check if already running
  local existing_pid
  if existing_pid=$(is_running); then
    echo "{\"status\": \"already_running\", \"url\": \"http://localhost:${PORT}\", \"pid\": ${existing_pid}, \"serve_dir\": \"${SERVE_DIR}\"}"
    return 0
  fi

  # Create serve directory
  mkdir -p "$SERVE_DIR"

  # Copy dashboard HTML as index.html
  local dashboard_src="${PLUGIN_DIR}/templates/dashboard.html"
  if [ -f "$dashboard_src" ]; then
    cp "$dashboard_src" "${SERVE_DIR}/index.html"
  else
    # Create a minimal placeholder if template doesn't exist yet
    echo "<html><body><h1>Flight Mode Dashboard</h1><p>Dashboard template not found at ${dashboard_src}</p></body></html>" > "${SERVE_DIR}/index.html"
  fi

  # Create initial empty data files
  echo '{}' > "${SERVE_DIR}/route-data.json"
  echo '{}' > "${SERVE_DIR}/live-data.json"

  # Start Python HTTP server in background
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SERVE_DIR" > /dev/null 2>&1 &
  local server_pid=$!

  # Verify the server started
  sleep 0.3
  if kill -0 "$server_pid" 2>/dev/null; then
    echo "$server_pid" > "$PID_FILE"
    echo "{\"status\": \"started\", \"url\": \"http://localhost:${PORT}\", \"pid\": ${server_pid}, \"serve_dir\": \"${SERVE_DIR}\"}"
  else
    echo "{\"status\": \"error\", \"message\": \"Server failed to start\"}"
    return 1
  fi
}

cmd_stop() {
  local existing_pid
  if existing_pid=$(is_running); then
    kill "$existing_pid" 2>/dev/null || true
    # Wait briefly for process to die
    local waited=0
    while kill -0 "$existing_pid" 2>/dev/null && [ "$waited" -lt 10 ]; do
      sleep 0.1
      waited=$((waited + 1))
    done
    # Force kill if still alive
    if kill -0 "$existing_pid" 2>/dev/null; then
      kill -9 "$existing_pid" 2>/dev/null || true
    fi
    # Clean up
    rm -rf "$SERVE_DIR"
    echo "{\"status\": \"stopped\"}"
  else
    # Clean up stale directory if it exists
    [ -d "$SERVE_DIR" ] && rm -rf "$SERVE_DIR"
    echo "{\"status\": \"not_running\"}"
  fi
}

cmd_status() {
  local existing_pid
  if existing_pid=$(is_running); then
    echo "{\"status\": \"running\", \"url\": \"http://localhost:${PORT}\", \"pid\": ${existing_pid}, \"serve_dir\": \"${SERVE_DIR}\"}"
  else
    echo "{\"status\": \"not_running\"}"
  fi
}

cmd_write_route() {
  local data
  data=$(echo "$INPUT" | jq -c '.data // {}')

  if [ ! -d "$SERVE_DIR" ]; then
    echo "{\"status\": \"error\", \"message\": \"Dashboard not running. Start it first.\"}"
    return 1
  fi

  echo "$data" > "${SERVE_DIR}/route-data.json"
  echo "{\"status\": \"written\", \"file\": \"route-data.json\"}"
}

cmd_write_live() {
  local data
  data=$(echo "$INPUT" | jq -c '.data // {}')

  if [ ! -d "$SERVE_DIR" ]; then
    echo "{\"status\": \"error\", \"message\": \"Dashboard not running. Start it first.\"}"
    return 1
  fi

  echo "$data" > "${SERVE_DIR}/live-data.json"
  echo "{\"status\": \"written\", \"file\": \"live-data.json\"}"
}

# Dispatch command
case "${COMMAND}" in
  start)
    cmd_start
    ;;
  stop)
    cmd_stop
    ;;
  status)
    cmd_status
    ;;
  write-route)
    cmd_write_route
    ;;
  write-live)
    cmd_write_live
    ;;
  *)
    echo "{\"status\": \"error\", \"message\": \"Unknown command: ${COMMAND}. Use: start, stop, status, write-route, write-live\"}"
    exit 1
    ;;
esac

exit 0
