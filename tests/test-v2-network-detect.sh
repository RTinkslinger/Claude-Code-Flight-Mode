#!/bin/bash
# Flight Mode — V2 Test Suite: network-detect.sh
# Tests WiFi network detection, SSID classification, and wifi-ssids.json data.
# Since we can't control the actual WiFi SSID, these tests validate script behavior
# and data file structure.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$PLUGIN_DIR/scripts/network-detect.sh"
SSIDS_FILE="$PLUGIN_DIR/data/wifi-ssids.json"
PASS=0
FAIL=0
SKIP=0
LOG=""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { LOG+="$1"$'\n'; echo -e "$1"; }
pass() { PASS=$((PASS+1)); log "${GREEN}  PASS${NC} $1"; }
fail() { FAIL=$((FAIL+1)); log "${RED}  FAIL${NC} $1 — $2"; }
skip() { SKIP=$((SKIP+1)); log "${YELLOW}  SKIP${NC} $1 — $2"; }
section() { log ""; log "${CYAN}━━━ $1 ━━━${NC}"; }

# ═══════════════════════════════════════════════════
# ND.1–ND.5: Script Behavior Tests
# ═══════════════════════════════════════════════════
section "ND.1–ND.5: Script Behavior"

# ND.1: Script exists and is executable
if [ -x "$SCRIPT" ]; then
  pass "ND.1 network-detect.sh exists and is executable"
elif [ -f "$SCRIPT" ]; then
  fail "ND.1 network-detect.sh executable" "exists but not executable"
else
  fail "ND.1 network-detect.sh exists" "file missing at $SCRIPT"
fi

# ND.2: Script outputs valid JSON
OUTPUT=$(echo '{"plugin_dir": "'"$PLUGIN_DIR"'"}' | bash "$SCRIPT" 2>/dev/null)
RC=$?
if [ $RC -eq 0 ] && echo "$OUTPUT" | jq . >/dev/null 2>&1; then
  pass "ND.2 script outputs valid JSON"
else
  fail "ND.2 valid JSON output" "rc=$RC output=$OUTPUT"
fi

# ND.3: Output has required fields
REQUIRED_FIELDS=("ssid" "type" "provider" "airline_codes" "confidence")
ALL_FIELDS_OK=true
for field in "${REQUIRED_FIELDS[@]}"; do
  if ! echo "$OUTPUT" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
    ALL_FIELDS_OK=false
    fail "ND.3 required field '$field'" "missing from output"
  fi
done
if [ "$ALL_FIELDS_OK" = "true" ]; then
  pass "ND.3 output has all required fields (ssid, type, provider, airline_codes, confidence)"
fi

# ND.4: Runs without error when passed plugin_dir via stdin
OUTPUT=$(echo '{"plugin_dir": "'"$PLUGIN_DIR"'"}' | bash "$SCRIPT" 2>/dev/null)
RC=$?
if [ $RC -eq 0 ]; then
  pass "ND.4 runs without error with plugin_dir via stdin"
else
  fail "ND.4 run with plugin_dir" "rc=$RC"
fi

# ND.5: Handles empty JSON input gracefully
OUTPUT=$(echo '{}' | bash "$SCRIPT" 2>/dev/null)
RC=$?
if [ $RC -eq 0 ]; then
  pass "ND.5 handles empty JSON input gracefully (rc=0)"
else
  fail "ND.5 empty JSON input" "rc=$RC"
fi

# ═══════════════════════════════════════════════════
# ND.6–ND.10: wifi-ssids.json Data Validation
# ═══════════════════════════════════════════════════
section "ND.6–ND.10: wifi-ssids.json Data Validation"

# ND.6: wifi-ssids.json is valid JSON and has airline_patterns array
if [ ! -f "$SSIDS_FILE" ]; then
  fail "ND.6 wifi-ssids.json exists" "file missing at $SSIDS_FILE"
else
  if jq . "$SSIDS_FILE" >/dev/null 2>&1; then
    AP_COUNT=$(jq '.airline_patterns | length' "$SSIDS_FILE" 2>/dev/null)
    if [ -n "$AP_COUNT" ] && [ "$AP_COUNT" -gt 0 ] 2>/dev/null; then
      pass "ND.6 wifi-ssids.json valid JSON with $AP_COUNT airline_patterns"
    else
      fail "ND.6 airline_patterns" "array empty or missing"
    fi
  else
    fail "ND.6 wifi-ssids.json" "invalid JSON"
  fi
fi

# ND.7: wifi-ssids.json has airport_patterns array
AIRPORT_COUNT=$(jq '.airport_patterns | length' "$SSIDS_FILE" 2>/dev/null)
if [ -n "$AIRPORT_COUNT" ] && [ "$AIRPORT_COUNT" -gt 0 ] 2>/dev/null; then
  pass "ND.7 wifi-ssids.json has airport_patterns array ($AIRPORT_COUNT entries)"
else
  fail "ND.7 airport_patterns" "array empty or missing"
fi

# ND.8: Each airline pattern has required fields (pattern, provider, airlines)
AIRLINE_PATTERNS_OK=true
AIRLINE_PATTERN_COUNT=$(jq '.airline_patterns | length' "$SSIDS_FILE" 2>/dev/null)
for i in $(seq 0 $((AIRLINE_PATTERN_COUNT - 1))); do
  HAS_PATTERN=$(jq -r ".airline_patterns[$i] | has(\"pattern\")" "$SSIDS_FILE" 2>/dev/null)
  HAS_PROVIDER=$(jq -r ".airline_patterns[$i] | has(\"provider\")" "$SSIDS_FILE" 2>/dev/null)
  HAS_AIRLINES=$(jq -r ".airline_patterns[$i] | has(\"airlines\")" "$SSIDS_FILE" 2>/dev/null)
  if [ "$HAS_PATTERN" != "true" ] || [ "$HAS_PROVIDER" != "true" ] || [ "$HAS_AIRLINES" != "true" ]; then
    AIRLINE_PATTERNS_OK=false
    PATTERN_NAME=$(jq -r ".airline_patterns[$i].pattern // \"index $i\"" "$SSIDS_FILE" 2>/dev/null)
    fail "ND.8 airline pattern '$PATTERN_NAME'" "missing required fields (pattern/provider/airlines)"
    break
  fi
done
if [ "$AIRLINE_PATTERNS_OK" = "true" ]; then
  pass "ND.8 all $AIRLINE_PATTERN_COUNT airline patterns have required fields"
fi

# ND.9: Known SSIDs in data file
section "ND.9: Known SSID Patterns"
KNOWN_SSIDS=("gogoinflight" "DeltaWiFi" "SouthwestWiFi" "United_WiFi" "AAInflight" "EmiratesWiFi" "CathayPacific")
for ssid in "${KNOWN_SSIDS[@]}"; do
  if jq -e ".airline_patterns[] | select(.pattern == \"$ssid\")" "$SSIDS_FILE" >/dev/null 2>&1; then
    pass "ND.9 known SSID '$ssid' present"
  else
    fail "ND.9 known SSID '$ssid'" "not found in airline_patterns"
  fi
done

# ND.10: Airport patterns include key patterns
section "ND.10: Airport SSID Patterns"
for pattern_check in "Free.*WiFi" "Boingo"; do
  if jq -e ".airport_patterns[] | select(.pattern == \"$pattern_check\")" "$SSIDS_FILE" >/dev/null 2>&1; then
    pass "ND.10 airport pattern '$pattern_check' present"
  else
    fail "ND.10 airport pattern '$pattern_check'" "not found in airport_patterns"
  fi
done

# ═══════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════
section "SUMMARY"
TOTAL=$((PASS + FAIL + SKIP))
log ""
log "  ${GREEN}Passed: $PASS${NC}"
log "  ${RED}Failed: $FAIL${NC}"
log "  ${YELLOW}Skipped: $SKIP${NC}"
log "  Total:  $TOTAL"
log ""

if [ $FAIL -eq 0 ]; then
  log "${GREEN}All network-detect tests passed!${NC}"
else
  log "${RED}$FAIL test(s) failed — see details above${NC}"
fi

exit $FAIL
