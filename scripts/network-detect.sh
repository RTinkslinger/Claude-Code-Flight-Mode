#!/bin/bash
# Flight Mode — WiFi Network Type Detection (macOS)
# Detects current WiFi SSID and classifies it as airline, airport, lounge, or other.
#
# Input: JSON on stdin  {"plugin_dir": "/path/to/plugin"}
#        or env var CLAUDE_PLUGIN_ROOT
# Output: JSON to stdout with network classification

set -uo pipefail

# ---------------------------------------------------------------------------
# Resolve plugin directory
# ---------------------------------------------------------------------------
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-}"

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

if [ -z "$PLUGIN_DIR" ]; then
  PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi

SSIDS_FILE="$PLUGIN_DIR/data/wifi-ssids.json"

# ---------------------------------------------------------------------------
# Helper: emit JSON result
# ---------------------------------------------------------------------------
emit_result() {
  local ssid_val="$1"
  local type_val="$2"
  local provider_val="$3"
  local airlines_val="$4"   # JSON array string e.g. ["CX","BA"] or null
  local confidence_val="$5"

  # Quote or null for strings
  local sq
  if [ "$ssid_val" = "null" ]; then sq="null"; else sq="\"$ssid_val\""; fi
  local pq
  if [ "$provider_val" = "null" ]; then pq="null"; else pq="\"$provider_val\""; fi

  cat <<EOJSON
{
  "ssid": $sq,
  "type": "$type_val",
  "provider": $pq,
  "airline_codes": $airlines_val,
  "confidence": "$confidence_val"
}
EOJSON
  exit 0
}

# ---------------------------------------------------------------------------
# 1. Get current WiFi SSID
# ---------------------------------------------------------------------------
SSID=""

# Primary method: airport utility
SSID=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null \
  | grep ' SSID' | head -1 | awk '{$1=""; print substr($0,2)}') || true

# Fallback: networksetup
if [ -z "$SSID" ]; then
  SSID=$(networksetup -getairportnetwork en0 2>/dev/null | awk -F': ' '{print $2}') || true
fi

# Trim whitespace
SSID=$(echo "$SSID" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# No WiFi connected
if [ -z "$SSID" ] || [ "$SSID" = "off" ] || echo "$SSID" | grep -qi "not associated" ; then
  emit_result "null" "none" "null" "null" "high"
fi

# ---------------------------------------------------------------------------
# 2. Check if wifi-ssids.json exists
# ---------------------------------------------------------------------------
if [ ! -f "$SSIDS_FILE" ]; then
  # No pattern file — return what we know
  emit_result "$SSID" "other" "null" "null" "low"
fi

# ---------------------------------------------------------------------------
# 3. Match against airline patterns
# ---------------------------------------------------------------------------
match=$(SSID_VAR="$SSID" SSIDS_VAR="$SSIDS_FILE" python3 -c "
import json, re, sys, os

ssid = os.environ.get('SSID_VAR', '')
ssids_file = os.environ.get('SSIDS_VAR', '')

with open(ssids_file) as f:
    data = json.load(f)

# Check airline patterns
for entry in data.get('airline_patterns', []):
    pattern = entry['pattern']
    if re.search(pattern, ssid, re.IGNORECASE):
        airlines_json = json.dumps(entry.get('airlines', []))
        provider = entry.get('provider', 'unknown')
        # Exact match = high confidence, regex/partial = medium
        if pattern.lower() == ssid.lower():
            confidence = 'high'
        elif ssid.lower().startswith(pattern.lower()) or pattern.lower().startswith(ssid.lower()):
            confidence = 'high'
        else:
            confidence = 'medium'
        print(f'airline|{provider}|{airlines_json}|{confidence}')
        sys.exit(0)

# Check airport/lounge patterns
for entry in data.get('airport_patterns', []):
    pattern = entry['pattern']
    if re.search(pattern, ssid, re.IGNORECASE):
        ptype = entry.get('type', 'airport')
        print(f'{ptype}|null|null|medium')
        sys.exit(0)

# No match
print('other|null|null|low')
" 2>/dev/null) || true

if [ -z "$match" ]; then
  # Python failed or no match — return other
  emit_result "$SSID" "other" "null" "null" "low"
fi

# Parse the pipe-delimited result
IFS='|' read -r net_type provider airlines confidence <<< "$match"

# Normalize null strings
[ "$provider" = "null" ] && provider="null"
[ "$airlines" = "null" ] && airlines="null"

emit_result "$SSID" "$net_type" "$provider" "$airlines" "$confidence"
