#!/bin/bash
# Flight Mode — Preflight Orchestrator
# Runs ALL environment checks deterministically. Called via !`command` in SKILL.md.
# Input: $1 = user arguments (may be empty), $2 = plugin directory
# Output: Single JSON blob with parse, network, api, dashboard, lookup results
set -uo pipefail

FLIGHT_ARGS="${1:-}"
PLUGIN_DIR="${2:-${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}}"

SCRIPTS_DIR="$PLUGIN_DIR/scripts"
CWD="$(pwd)"

# --- 1. Parse flight input ---
# parse-flight.sh accepts: stdin JSON {"input": "...", "plugin_dir": "..."} OR $1 as flight string
# Using stdin JSON for full control over both fields.
PARSE_RESULT=$(jq -n --arg input "$FLIGHT_ARGS" --arg pd "$PLUGIN_DIR" '{input: $input, plugin_dir: $pd}' \
  | bash "$SCRIPTS_DIR/parse-flight.sh" 2>/dev/null) || PARSE_RESULT='{"confidence":"none"}'

# --- 2. Network detection ---
# network-detect.sh accepts: stdin JSON {"plugin_dir": "..."} OR env var CLAUDE_PLUGIN_ROOT
NETWORK_RESULT=$(jq -n --arg pd "$PLUGIN_DIR" '{plugin_dir: $pd}' \
  | bash "$SCRIPTS_DIR/network-detect.sh" 2>/dev/null) || NETWORK_RESULT='{"type":"unknown","ssid":null}'

# --- 3. API availability check ---
# flight-check.sh accepts: stdin JSON {"cwd": "...", "plugin_dir": "..."} OR env var CLAUDE_PLUGIN_ROOT
API_RESULT=$(jq -n --arg cwd "$CWD" --arg pd "$PLUGIN_DIR" '{cwd: $cwd, plugin_dir: $pd}' \
  | bash "$SCRIPTS_DIR/flight-check.sh" 2>/dev/null) || API_RESULT='{"verdict":"OFFLINE"}'

# --- 4. Start dashboard ---
# dashboard-server.sh reads ALL input from stdin JSON: {command, cwd, plugin_dir, port}
DASHBOARD_RESULT=$(jq -n --arg cwd "$CWD" --arg pd "$PLUGIN_DIR" '{command: "start", cwd: $cwd, plugin_dir: $pd}' \
  | bash "$SCRIPTS_DIR/dashboard-server.sh" 2>/dev/null) || DASHBOARD_RESULT='{"status":"error"}'

# --- 5. Determine what's missing ---
AIRLINE_CODE=$(echo "$PARSE_RESULT" | jq -r '.airline_code // empty')
ORIGIN=$(echo "$PARSE_RESULT" | jq -r '.origin // empty')
DESTINATION=$(echo "$PARSE_RESULT" | jq -r '.destination // empty')
NEEDS_ROUTE=$(echo "$PARSE_RESULT" | jq -r '.needs_route // false')
CONFIDENCE=$(echo "$PARSE_RESULT" | jq -r '.confidence // "none"')

MISSING="[]"
READY="false"

if [ -z "$AIRLINE_CODE" ] || [ "$CONFIDENCE" = "none" ]; then
  MISSING='["airline","route"]'
elif [ "$NEEDS_ROUTE" = "true" ] || [ -z "$ORIGIN" ] || [ -z "$DESTINATION" ]; then
  MISSING='["route"]'
else
  READY="true"
fi

# --- 6. If ready, run lookup ---
LOOKUP_RESULT="null"
if [ "$READY" = "true" ]; then
  DASHBOARD_DIR=$(echo "$DASHBOARD_RESULT" | jq -r '.serve_dir // empty')
  LOOKUP_RESULT=$(jq -n --arg ac "$AIRLINE_CODE" --arg orig "$ORIGIN" --arg dest "$DESTINATION" --arg pd "$PLUGIN_DIR" --arg dd "$DASHBOARD_DIR" \
    '{airline_code: $ac, origin: $orig, destination: $dest, plugin_dir: $pd, dashboard_dir: $dd}' \
    | bash "$SCRIPTS_DIR/flight-on-lookup.sh" 2>/dev/null) || LOOKUP_RESULT="null"
fi

# --- 7. Assemble final output ---
PARSE_VAR="$PARSE_RESULT" \
NETWORK_VAR="$NETWORK_RESULT" \
API_VAR="$API_RESULT" \
DASHBOARD_VAR="$DASHBOARD_RESULT" \
LOOKUP_VAR="$LOOKUP_RESULT" \
READY_VAR="$READY" \
MISSING_VAR="$MISSING" \
python3 -c "
import json, os
def p(v):
    try: return json.loads(v)
    except: return None

result = {
    'parse': p(os.environ['PARSE_VAR']),
    'network': p(os.environ['NETWORK_VAR']),
    'api': p(os.environ['API_VAR']),
    'dashboard': p(os.environ['DASHBOARD_VAR']),
    'lookup': p(os.environ['LOOKUP_VAR']),
    'ready': os.environ['READY_VAR'] == 'true',
    'missing': json.loads(os.environ['MISSING_VAR'])
}
print(json.dumps(result, indent=2))
" 2>/dev/null || echo '{"error":"preflight assembly failed"}'
