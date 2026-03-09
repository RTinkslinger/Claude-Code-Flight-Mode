#!/bin/bash
# Flight Mode — Pre-flight / In-flight API Availability Checker
# Tests DNS, HTTPS reachability, geo-IP egress, latency, and download speed.
#
# Input: JSON on stdin  {"cwd": "/path", "plugin_dir": "/path/to/plugin"}
#        or env var CLAUDE_PLUGIN_ROOT
# Output: JSON to stdout with verdict: GO | CAUTION | BLOCKED | OFFLINE

set -uo pipefail

# ---------------------------------------------------------------------------
# Resolve plugin directory
# ---------------------------------------------------------------------------
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-}"

# Try to read from stdin (non-blocking)
if [ -t 0 ]; then
  STDIN_JSON=""
else
  STDIN_JSON=$(cat 2>/dev/null || true)
fi

if [ -n "$STDIN_JSON" ]; then
  STDIN_PLUGIN_DIR=$(echo "$STDIN_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('plugin_dir',''))" 2>/dev/null || true)
  if [ -n "$STDIN_PLUGIN_DIR" ]; then
    PLUGIN_DIR="$STDIN_PLUGIN_DIR"
  fi
fi

# Fallback: script's own directory -> parent
if [ -z "$PLUGIN_DIR" ]; then
  PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi

COUNTRIES_FILE="$PLUGIN_DIR/data/supported-countries.json"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
api_reachable=false
api_latency_ms=0
http_status=0
egress_country="null"
egress_city="null"
egress_org="null"
country_supported=false
ping_avg_ms=0
download_speed_bps=0
verdict="OFFLINE"
warning="null"

# ---------------------------------------------------------------------------
# Helper: emit JSON result and exit
# ---------------------------------------------------------------------------
emit_result() {
  # Quote strings, leave booleans/numbers bare
  local w
  if [ "$warning" = "null" ]; then
    w="null"
  else
    w="\"$warning\""
  fi

  local ec
  if [ "$egress_country" = "null" ]; then ec="null"; else ec="\"$egress_country\""; fi
  local eci
  if [ "$egress_city" = "null" ]; then eci="null"; else eci="\"$egress_city\""; fi
  local eo
  if [ "$egress_org" = "null" ]; then eo="null"; else eo="\"$egress_org\""; fi

  cat <<EOJSON
{
  "api_reachable": $api_reachable,
  "api_latency_ms": $api_latency_ms,
  "http_status": $http_status,
  "egress_country": $ec,
  "egress_city": $eci,
  "egress_org": $eo,
  "country_supported": $country_supported,
  "ping_avg_ms": $ping_avg_ms,
  "download_speed_bps": $download_speed_bps,
  "verdict": "$verdict",
  "warning": $w
}
EOJSON
  exit 0
}

# ---------------------------------------------------------------------------
# 1. DNS resolution of api.anthropic.com
# ---------------------------------------------------------------------------
dns_ok=false
if host api.anthropic.com >/dev/null 2>&1; then
  dns_ok=true
elif nslookup api.anthropic.com >/dev/null 2>&1; then
  dns_ok=true
fi

if [ "$dns_ok" = "false" ]; then
  # No DNS = likely offline
  verdict="OFFLINE"
  warning="DNS resolution failed — no network connectivity"
  emit_result
fi

# ---------------------------------------------------------------------------
# 2. HTTPS reachability + timing
# ---------------------------------------------------------------------------
curl_output=$(curl -o /dev/null -s -w '%{http_code} %{time_total}' \
  --max-time 5 --connect-timeout 5 \
  https://api.anthropic.com 2>/dev/null) || true

if [ -n "$curl_output" ]; then
  http_status=$(echo "$curl_output" | awk '{print $1}')
  time_total=$(echo "$curl_output" | awk '{print $2}')

  # Convert seconds to ms (integer)
  if [ -n "$time_total" ] && [ "$time_total" != "0.000000" ]; then
    api_latency_ms=$(python3 -c "print(int(float('$time_total') * 1000))" 2>/dev/null || echo 0)
  fi

  # Any HTTP response (even 401/403) means the API endpoint is reachable
  if [ "$http_status" -gt 0 ] 2>/dev/null; then
    api_reachable=true
  fi
fi

if [ "$api_reachable" = "false" ]; then
  verdict="BLOCKED"
  warning="API endpoint unreachable — HTTPS connection failed"
  # Continue to collect remaining metrics anyway
fi

# ---------------------------------------------------------------------------
# 3. Geo-IP lookup via ipinfo.io
# ---------------------------------------------------------------------------
geoip_json=$(curl -s --max-time 5 --connect-timeout 5 https://ipinfo.io/json 2>/dev/null) || true

if [ -n "$geoip_json" ]; then
  egress_country=$(echo "$geoip_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('country',''))" 2>/dev/null || true)
  egress_city=$(echo "$geoip_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('city',''))" 2>/dev/null || true)
  egress_org=$(echo "$geoip_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('org',''))" 2>/dev/null || true)

  # Sanitize empty values
  [ -z "$egress_country" ] && egress_country="null"
  [ -z "$egress_city" ] && egress_city="null"
  [ -z "$egress_org" ] && egress_org="null"
fi

# ---------------------------------------------------------------------------
# 4. Cross-reference egress country against supported-countries.json
# ---------------------------------------------------------------------------
if [ "$egress_country" != "null" ] && [ -f "$COUNTRIES_FILE" ]; then
  # Check if country is in the supported list
  is_supported=$(COUNTRIES_VAR="$COUNTRIES_FILE" COUNTRY_VAR="$egress_country" python3 -c "
import json, sys, os
with open(os.environ['COUNTRIES_VAR']) as f:
    data = json.load(f)
country = os.environ.get('COUNTRY_VAR', '')
if country in data.get('supported', []):
    print('supported')
elif country in data.get('explicitly_excluded', []):
    note = data.get('excluded_notes', {}).get(country, 'Excluded region')
    print('excluded:' + note)
else:
    print('unknown')
" 2>/dev/null || echo "unknown")

  case "$is_supported" in
    supported)
      country_supported=true
      ;;
    excluded:*)
      country_supported=false
      note="${is_supported#excluded:}"
      warning="Egress via $egress_country — $note"
      ;;
    *)
      # Not in either list — could be fine, mark as caution
      country_supported=false
      warning="Egress country $egress_country not in known supported list"
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# 5. Latency baseline (ping 8.8.8.8)
# ---------------------------------------------------------------------------
ping_output=$(ping -c 3 -W 5 8.8.8.8 2>/dev/null) || true
if [ -n "$ping_output" ]; then
  # macOS ping: round-trip min/avg/max/stddev = X/Y/Z/W ms
  ping_avg=$(echo "$ping_output" | tail -1 | awk -F'/' '{print $5}' 2>/dev/null || true)
  if [ -n "$ping_avg" ]; then
    ping_avg_ms=$(python3 -c "print(int(float('$ping_avg')))" 2>/dev/null || echo 0)
  fi
fi

# ---------------------------------------------------------------------------
# 6. Download speed test (100KB from Cloudflare)
# ---------------------------------------------------------------------------
dl_output=$(curl -o /dev/null -s -w '%{speed_download}' \
  --max-time 10 --connect-timeout 5 \
  "https://speed.cloudflare.com/__down?bytes=100000" 2>/dev/null) || true

if [ -n "$dl_output" ]; then
  download_speed_bps=$(python3 -c "print(int(float('$dl_output')))" 2>/dev/null || echo 0)
fi

# ---------------------------------------------------------------------------
# 7. Compute verdict
# ---------------------------------------------------------------------------
if [ "$api_reachable" = "false" ]; then
  # Already set above, but refine
  if [ "$dns_ok" = "false" ]; then
    verdict="OFFLINE"
  elif [ "$country_supported" = "false" ] && [ "$egress_country" != "null" ]; then
    verdict="BLOCKED"
    # warning already set from country check
  else
    verdict="BLOCKED"
  fi
elif [ "$country_supported" = "false" ] && [ "$egress_country" != "null" ]; then
  verdict="BLOCKED"
  # warning already set
elif [ "$api_latency_ms" -gt 3000 ] 2>/dev/null; then
  verdict="CAUTION"
  if [ "$warning" = "null" ]; then
    warning="Very high API latency (${api_latency_ms}ms) — expect timeouts"
  fi
elif [ "$ping_avg_ms" -gt 1500 ] 2>/dev/null; then
  verdict="CAUTION"
  if [ "$warning" = "null" ]; then
    warning="Extremely high network latency (${ping_avg_ms}ms avg ping)"
  fi
elif [ "$download_speed_bps" -gt 0 ] && [ "$download_speed_bps" -lt 50000 ] 2>/dev/null; then
  verdict="CAUTION"
  if [ "$warning" = "null" ]; then
    warning="Very low bandwidth (${download_speed_bps} bytes/s) — large file operations will fail"
  fi
else
  verdict="GO"
fi

emit_result
