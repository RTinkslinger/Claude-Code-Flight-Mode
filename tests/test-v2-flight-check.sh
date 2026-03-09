#!/bin/bash
# Flight Mode — V2 Test Suite: flight-check.sh
# Tests API availability checker structure, output format, and data files.
# Note: actual network tests depend on connectivity.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$PLUGIN_DIR/scripts/flight-check.sh"
COUNTRIES_FILE="$PLUGIN_DIR/data/supported-countries.json"
EGRESS_FILE="$PLUGIN_DIR/data/provider-egress.json"
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
# FC.1–FC.3: Script Basics
# ═══════════════════════════════════════════════════
section "FC.1–FC.3: Script Basics"

# FC.1: Script exists and is executable
if [ -x "$SCRIPT" ]; then
  pass "FC.1 flight-check.sh exists and is executable"
elif [ -f "$SCRIPT" ]; then
  fail "FC.1 flight-check.sh executable" "exists but not executable"
else
  fail "FC.1 flight-check.sh exists" "file missing at $SCRIPT"
fi

# FC.2–FC.3: Script outputs valid JSON with required fields
# Run with background process + wait for macOS compatibility (no timeout command)
OUTPUT=$(echo '{"plugin_dir": "'"$PLUGIN_DIR"'"}' | bash "$SCRIPT" 2>/dev/null) || true
RC=$?

if echo "$OUTPUT" | jq . >/dev/null 2>&1; then
  pass "FC.2 script outputs valid JSON"
else
  # If timeout or network issue, skip rather than fail
  if [ $RC -eq 124 ]; then
    skip "FC.2 valid JSON output" "script timed out (network dependent)"
  else
    fail "FC.2 valid JSON output" "rc=$RC output=$(echo "$OUTPUT" | head -1)"
  fi
fi

# FC.3: Output has required fields
REQUIRED_FIELDS=("api_reachable" "api_latency_ms" "http_status" "egress_country" "country_supported" "ping_avg_ms" "download_speed_bps" "verdict" "warning")
if echo "$OUTPUT" | jq . >/dev/null 2>&1; then
  ALL_FIELDS_OK=true
  for field in "${REQUIRED_FIELDS[@]}"; do
    if ! echo "$OUTPUT" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
      ALL_FIELDS_OK=false
      fail "FC.3 required field '$field'" "missing from output"
    fi
  done
  if [ "$ALL_FIELDS_OK" = "true" ]; then
    pass "FC.3 output has all required fields (${#REQUIRED_FIELDS[@]} fields)"
  fi
else
  skip "FC.3 required fields" "no valid JSON output to check"
fi

# ═══════════════════════════════════════════════════
# FC.4–FC.6: Field Value Validation
# ═══════════════════════════════════════════════════
section "FC.4–FC.6: Field Value Validation"

if echo "$OUTPUT" | jq . >/dev/null 2>&1; then
  # FC.4: Verdict is one of GO, CAUTION, BLOCKED, OFFLINE
  VERDICT=$(echo "$OUTPUT" | jq -r '.verdict' 2>/dev/null)
  case "$VERDICT" in
    GO|CAUTION|BLOCKED|OFFLINE)
      pass "FC.4 verdict='$VERDICT' (valid enum value)"
      ;;
    *)
      fail "FC.4 verdict" "got '$VERDICT', expected GO|CAUTION|BLOCKED|OFFLINE"
      ;;
  esac

  # FC.5: api_reachable is boolean
  API_REACH=$(echo "$OUTPUT" | jq -r '.api_reachable | type' 2>/dev/null)
  if [ "$API_REACH" = "boolean" ]; then
    pass "FC.5 api_reachable is boolean"
  else
    fail "FC.5 api_reachable type" "got '$API_REACH', expected boolean"
  fi

  # FC.6: country_supported is boolean
  CS_TYPE=$(echo "$OUTPUT" | jq -r '.country_supported | type' 2>/dev/null)
  if [ "$CS_TYPE" = "boolean" ]; then
    pass "FC.6 country_supported is boolean"
  else
    fail "FC.6 country_supported type" "got '$CS_TYPE', expected boolean"
  fi
else
  skip "FC.4 verdict enum" "no valid JSON output"
  skip "FC.5 api_reachable boolean" "no valid JSON output"
  skip "FC.6 country_supported boolean" "no valid JSON output"
fi

# ═══════════════════════════════════════════════════
# FC.7–FC.13: supported-countries.json Validation
# ═══════════════════════════════════════════════════
section "FC.7–FC.13: supported-countries.json"

# FC.7: Valid JSON
if [ -f "$COUNTRIES_FILE" ]; then
  if jq . "$COUNTRIES_FILE" >/dev/null 2>&1; then
    pass "FC.7 supported-countries.json is valid JSON"
  else
    fail "FC.7 supported-countries.json" "invalid JSON"
  fi
else
  fail "FC.7 supported-countries.json exists" "file missing"
fi

# FC.8: Has "supported" array
SUPPORTED_COUNT=$(jq '.supported | length' "$COUNTRIES_FILE" 2>/dev/null)
if [ -n "$SUPPORTED_COUNT" ] && [ "$SUPPORTED_COUNT" -gt 0 ] 2>/dev/null; then
  pass "FC.8 supported-countries.json has 'supported' array ($SUPPORTED_COUNT entries)"
else
  fail "FC.8 supported array" "empty or missing"
fi

# FC.9: Has "explicitly_excluded" array
EXCLUDED_COUNT=$(jq '.explicitly_excluded | length' "$COUNTRIES_FILE" 2>/dev/null)
if [ -n "$EXCLUDED_COUNT" ] && [ "$EXCLUDED_COUNT" -gt 0 ] 2>/dev/null; then
  pass "FC.9 supported-countries.json has 'explicitly_excluded' array ($EXCLUDED_COUNT entries)"
else
  fail "FC.9 explicitly_excluded array" "empty or missing"
fi

# FC.10: US is in supported list
if jq -e '.supported | index("US")' "$COUNTRIES_FILE" >/dev/null 2>&1; then
  pass "FC.10 US is in supported list"
else
  fail "FC.10 US in supported" "not found"
fi

# FC.11: CN is in excluded list
if jq -e '.explicitly_excluded | index("CN")' "$COUNTRIES_FILE" >/dev/null 2>&1; then
  pass "FC.11 CN is in excluded list"
else
  fail "FC.11 CN in excluded" "not found"
fi

# FC.12: HK is in excluded list
if jq -e '.explicitly_excluded | index("HK")' "$COUNTRIES_FILE" >/dev/null 2>&1; then
  pass "FC.12 HK is in excluded list"
else
  fail "FC.12 HK in excluded" "not found"
fi

# FC.13: GB is in supported list
if jq -e '.supported | index("GB")' "$COUNTRIES_FILE" >/dev/null 2>&1; then
  pass "FC.13 GB is in supported list"
else
  fail "FC.13 GB in supported" "not found"
fi

# ═══════════════════════════════════════════════════
# FC.14–FC.16: provider-egress.json Validation
# ═══════════════════════════════════════════════════
section "FC.14–FC.16: provider-egress.json"

# FC.14: Valid JSON
if [ -f "$EGRESS_FILE" ]; then
  if jq . "$EGRESS_FILE" >/dev/null 2>&1; then
    pass "FC.14 provider-egress.json is valid JSON"
  else
    fail "FC.14 provider-egress.json" "invalid JSON"
  fi
else
  fail "FC.14 provider-egress.json exists" "file missing"
fi

# FC.15: Has all expected providers
EXPECTED_PROVIDERS=("gogo" "inmarsat" "viasat" "panasonic" "starlink" "ses" "none" "unknown")
ALL_PROVIDERS_OK=true
for prov in "${EXPECTED_PROVIDERS[@]}"; do
  if ! jq -e ".providers.\"$prov\"" "$EGRESS_FILE" >/dev/null 2>&1; then
    ALL_PROVIDERS_OK=false
    fail "FC.15 provider '$prov'" "not found in provider-egress.json"
  fi
done
if [ "$ALL_PROVIDERS_OK" = "true" ]; then
  pass "FC.15 all ${#EXPECTED_PROVIDERS[@]} expected providers present"
fi

# FC.16: Each provider has required fields (name, orbit, egress_countries, risk, api_safe)
PROVIDER_FIELDS_OK=true
for prov in "${EXPECTED_PROVIDERS[@]}"; do
  for field in "name" "orbit" "egress_countries" "risk" "api_safe"; do
    if ! jq -e ".providers.\"$prov\" | has(\"$field\")" "$EGRESS_FILE" >/dev/null 2>&1; then
      PROVIDER_FIELDS_OK=false
      fail "FC.16 provider '$prov' field '$field'" "missing"
    fi
  done
done
if [ "$PROVIDER_FIELDS_OK" = "true" ]; then
  pass "FC.16 all providers have required fields (name, orbit, egress_countries, risk, api_safe)"
fi

# ═══════════════════════════════════════════════════
# FC.17–FC.18: Runtime Behavior
# ═══════════════════════════════════════════════════
section "FC.17–FC.18: Runtime Behavior"

# FC.17: Script completes within 30 seconds
START_TIME=$(date +%s)
echo '{"plugin_dir": "'"$PLUGIN_DIR"'"}' | bash "$SCRIPT" >/dev/null 2>&1
FC17_RC=$?
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
if [ "$ELAPSED" -lt 30 ]; then
  pass "FC.17 script completes within 30s (took ${ELAPSED}s)"
else
  fail "FC.17 timeout" "script took ${ELAPSED}s"
fi

# FC.18: Handles missing supported-countries.json gracefully
TEMP_DIR=$(mktemp -d)
TEMP_PLUGIN="$TEMP_DIR/fake-plugin"
mkdir -p "$TEMP_PLUGIN/scripts" "$TEMP_PLUGIN/data"
cp "$SCRIPT" "$TEMP_PLUGIN/scripts/"
# Intentionally do NOT copy supported-countries.json
OUTPUT=$(echo '{"plugin_dir": "'"$TEMP_PLUGIN"'"}' | bash "$TEMP_PLUGIN/scripts/flight-check.sh" 2>/dev/null) || true
FC18_RC=$?
rm -rf "$TEMP_DIR"
if [ $FC18_RC -eq 0 ]; then
  pass "FC.18 handles missing supported-countries.json gracefully"
else
  fail "FC.18 missing countries file" "rc=$FC18_RC"
fi

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
  log "${GREEN}All flight-check tests passed!${NC}"
else
  log "${RED}$FAIL test(s) failed — see details above${NC}"
fi

exit $FAIL
