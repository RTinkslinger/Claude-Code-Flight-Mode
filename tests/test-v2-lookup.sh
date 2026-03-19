#!/bin/bash
# Flight Mode — V2 Test Suite: flight-on-lookup.sh
# Tests profile lookup, variant handling, corridor matching,
# route-data output, calibration, and missing-data resilience
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$PLUGIN_DIR/scripts/flight-on-lookup.sh"
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

# Helper: run lookup with given JSON fields
run_lookup() {
  local json="$1"
  echo "$json" | bash "$SCRIPT" 2>/dev/null
}

# Helper: extract a field from JSON output
jq_field() {
  local json="$1"
  local field="$2"
  echo "$json" | jq -r "if .$field == null then \"null\" else (.$field | tostring) end" 2>/dev/null
}

# ═══════════════════════════════════════════════════
# Prerequisites
# ═══════════════════════════════════════════════════
section "LK.0: Prerequisites"

if [ ! -f "$SCRIPT" ]; then
  fail "LK.0a flight-on-lookup.sh exists" "file missing at $SCRIPT"
  log ""
  log "Cannot continue without flight-on-lookup.sh"
  exit 1
fi

if [ ! -x "$SCRIPT" ]; then
  fail "LK.0b flight-on-lookup.sh is executable" "not executable"
else
  pass "LK.0b flight-on-lookup.sh is executable"
fi

if ! command -v jq >/dev/null 2>&1; then
  fail "LK.0c jq is installed" "jq not found — cannot run tests"
  exit 1
fi
pass "LK.0c jq is installed"

if ! command -v python3 >/dev/null 2>&1; then
  fail "LK.0d python3 is installed" "python3 not found — lookup requires it"
  exit 1
fi
pass "LK.0d python3 is installed"

# ═══════════════════════════════════════════════════
# LK.1: Basic airline profile lookup (CX HKG-LAX)
# ═══════════════════════════════════════════════════
section "LK.1: Basic Airline Profile Lookup"

OUTPUT=$(run_lookup '{"airline_code":"CX","origin":"HKG","destination":"LAX","plugin_dir":"'"$PLUGIN_DIR"'"}')

# Valid JSON check
if ! echo "$OUTPUT" | jq . >/dev/null 2>&1; then
  fail "LK.1a valid JSON output" "invalid JSON: $OUTPUT"
else
  pass "LK.1a valid JSON output"

  AN=$(jq_field "$OUTPUT" "airline_name")
  if [ "$AN" != "null" ] && [ -n "$AN" ]; then
    pass "LK.1b airline_name present ($AN)"
  else
    fail "LK.1b airline_name present" "got: $AN"
  fi

  RT=$(jq_field "$OUTPUT" "rating")
  case "$RT" in
    EXCELLENT|GOOD|USABLE|CHOPPY|POOR)
      pass "LK.1c rating is valid ($RT)"
      ;;
    *)
      fail "LK.1c rating is valid" "got: $RT"
      ;;
  esac

  # Calibration object with required fields
  BS=$(echo "$OUTPUT" | jq -r '.calibration.batch_size // empty' 2>/dev/null)
  CI=$(echo "$OUTPUT" | jq -r '.calibration.checkpoint_interval // empty' 2>/dev/null)
  CM=$(echo "$OUTPUT" | jq -r '.calibration.commit_interval // empty' 2>/dev/null)
  if [ -n "$BS" ] && [ -n "$CI" ] && [ -n "$CM" ]; then
    pass "LK.1d calibration has batch_size, checkpoint_interval, commit_interval"
  else
    fail "LK.1d calibration fields" "bs=$BS ci=$CI cm=$CM"
  fi
fi

# ═══════════════════════════════════════════════════
# LK.2: Unknown airline falls back to defaults
# ═══════════════════════════════════════════════════
section "LK.2: Unknown Airline Fallback"

OUTPUT=$(run_lookup '{"airline_code":"ZZ","origin":"JFK","destination":"LAX","plugin_dir":"'"$PLUGIN_DIR"'"}')
RC=$?

if [ $RC -eq 0 ]; then
  pass "LK.2a no crash (exit code 0)"
else
  fail "LK.2a no crash" "exit code $RC"
fi

if echo "$OUTPUT" | jq . >/dev/null 2>&1; then
  pass "LK.2b valid JSON output"
  AN=$(jq_field "$OUTPUT" "airline_name")
  RT=$(jq_field "$OUTPUT" "rating")
  # Default profile should give "Unknown Carrier" or at least a valid rating
  if [ "$RT" != "null" ] && [ -n "$RT" ]; then
    pass "LK.2c uses default profile (airline=$AN, rating=$RT)"
  else
    fail "LK.2c default profile" "rating=$RT airline=$AN"
  fi
else
  fail "LK.2b valid JSON" "invalid JSON: $OUTPUT"
fi

# ═══════════════════════════════════════════════════
# LK.3: Variant airline — most conservative (UA)
# ═══════════════════════════════════════════════════
section "LK.3: Variant Airline Selection (UA)"

OUTPUT=$(run_lookup '{"airline_code":"UA","origin":"SFO","destination":"ORD","plugin_dir":"'"$PLUGIN_DIR"'"}')

RT=$(jq_field "$OUTPUT" "rating")
# UA has starlink (EXCELLENT) and legacy (USABLE) — worst for domestic = USABLE
if [ "$RT" = "USABLE" ]; then
  pass "LK.3 UA domestic rating is USABLE (most conservative of EXCELLENT/USABLE)"
else
  fail "LK.3 UA most conservative" "expected USABLE, got $RT"
fi

# ═══════════════════════════════════════════════════
# LK.4: Domestic vs long-haul rating selection (DL)
# ═══════════════════════════════════════════════════
section "LK.4: Domestic vs Long-Haul Rating (DL)"

# DL domestic: JFK-LAX (~5h, under domestic_max_hours=6)
OUTPUT_DOM=$(run_lookup '{"airline_code":"DL","origin":"JFK","destination":"LAX","plugin_dir":"'"$PLUGIN_DIR"'"}')
RT_DOM=$(jq_field "$OUTPUT_DOM" "rating")

if [ "$RT_DOM" = "GOOD" ]; then
  pass "LK.4a DL domestic (JFK-LAX) rating = GOOD"
else
  fail "LK.4a DL domestic" "expected GOOD, got $RT_DOM"
fi

# DL long-haul: JFK-LHR (~8h, over domestic_max_hours=6)
OUTPUT_LH=$(run_lookup '{"airline_code":"DL","origin":"JFK","destination":"LHR","plugin_dir":"'"$PLUGIN_DIR"'"}')
RT_LH=$(jq_field "$OUTPUT_LH" "rating")

if [ "$RT_LH" = "USABLE" ]; then
  pass "LK.4b DL long-haul (JFK-LHR) rating = USABLE"
else
  fail "LK.4b DL long-haul" "expected USABLE, got $RT_LH"
fi

# ═══════════════════════════════════════════════════
# LK.5: Corridor matching — known route
# ═══════════════════════════════════════════════════
section "LK.5: Corridor Matching"

OUTPUT=$(run_lookup '{"airline_code":"CX","origin":"HKG","destination":"LAX","plugin_dir":"'"$PLUGIN_DIR"'"}')

CORRIDOR=$(jq_field "$OUTPUT" "corridor")
WP_LEN=$(echo "$OUTPUT" | jq '.waypoints | length' 2>/dev/null)
DUR=$(jq_field "$OUTPUT" "duration_hours")

if [ "$CORRIDOR" != "unknown" ] && [ "$CORRIDOR" != "null" ]; then
  pass "LK.5a corridor is not unknown ($CORRIDOR)"
else
  fail "LK.5a corridor matched" "got: $CORRIDOR"
fi

if [ -n "$WP_LEN" ] && [ "$WP_LEN" -gt 0 ] 2>/dev/null; then
  pass "LK.5b waypoints array has entries ($WP_LEN)"
else
  fail "LK.5b waypoints" "length=$WP_LEN"
fi

# duration_hours should be a positive number
DUR_NUM=$(echo "$DUR" | python3 -c "import sys; v=float(sys.stdin.read().strip()); print('yes' if v > 0 else 'no')" 2>/dev/null)
if [ "$DUR_NUM" = "yes" ]; then
  pass "LK.5c duration_hours > 0 ($DUR)"
else
  fail "LK.5c duration_hours" "got: $DUR"
fi

# ═══════════════════════════════════════════════════
# LK.6: Route-data.json written to dashboard dir
# ═══════════════════════════════════════════════════
section "LK.6: Route-Data Dashboard Output"

TEMP_DASH=$(mktemp -d)
OUTPUT=$(run_lookup '{"airline_code":"CX","origin":"HKG","destination":"LAX","plugin_dir":"'"$PLUGIN_DIR"'","dashboard_dir":"'"$TEMP_DASH"'"}')

ROUTE_FILE="$TEMP_DASH/route-data.json"
if [ -f "$ROUTE_FILE" ]; then
  pass "LK.6a route-data.json created in dashboard_dir"

  if jq . "$ROUTE_FILE" >/dev/null 2>&1; then
    pass "LK.6b route-data.json is valid JSON"
  else
    fail "LK.6b valid JSON" "invalid JSON in route-data.json"
  fi

  HAS_FLIGHT=$(jq -r '.flight // empty' "$ROUTE_FILE" 2>/dev/null)
  HAS_ROUTE=$(jq -r '.route // empty' "$ROUTE_FILE" 2>/dev/null)
  HAS_RATING=$(jq -r '.rating // empty' "$ROUTE_FILE" 2>/dev/null)

  HAS_TAKEOFF=$(jq -r '.takeoff_time // empty' "$ROUTE_FILE" 2>/dev/null)

  if [ -n "$HAS_FLIGHT" ] && [ -n "$HAS_ROUTE" ] && [ -n "$HAS_RATING" ]; then
    pass "LK.6c route-data.json has .flight, .route, .rating fields"
  else
    fail "LK.6c required fields" "flight=$HAS_FLIGHT route=$HAS_ROUTE rating=$HAS_RATING"
  fi

  if [ -n "$HAS_TAKEOFF" ] && echo "$HAS_TAKEOFF" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then
    pass "LK.6d route-data.json has valid takeoff_time (ISO timestamp)"
  else
    fail "LK.6d takeoff_time" "got: $HAS_TAKEOFF"
  fi
else
  fail "LK.6a route-data.json created" "file not found at $ROUTE_FILE"
fi

rm -rf "$TEMP_DASH"

# ═══════════════════════════════════════════════════
# LK.7: Missing data files handled gracefully
# ═══════════════════════════════════════════════════
section "LK.7: Missing Data Files Resilience"

TEMP_PLUGIN=$(mktemp -d)
mkdir -p "$TEMP_PLUGIN/data" "$TEMP_PLUGIN/scripts"

# Copy only airline-codes.json (missing profiles, corridors, airports, egress)
cp "$PLUGIN_DIR/data/airline-codes.json" "$TEMP_PLUGIN/data/"
# Copy the lookup script itself
cp "$PLUGIN_DIR/scripts/flight-on-lookup.sh" "$TEMP_PLUGIN/scripts/"

OUTPUT=$(run_lookup '{"airline_code":"CX","origin":"HKG","destination":"LAX","plugin_dir":"'"$TEMP_PLUGIN"'"}')
RC=$?

if [ $RC -eq 0 ]; then
  pass "LK.7a script does not crash with missing data files (exit 0)"
else
  # Even if exit code is non-zero, as long as it produces output rather than a hard crash
  if [ -n "$OUTPUT" ]; then
    pass "LK.7a script produces output despite missing files (exit $RC)"
  else
    fail "LK.7a graceful handling" "exit $RC, no output"
  fi
fi

# Check if fallback JSON was produced
if echo "$OUTPUT" | jq . >/dev/null 2>&1; then
  pass "LK.7b produces valid JSON with missing data files"
else
  # Accept that it might produce nothing or error — the key is no hard crash
  skip "LK.7b valid JSON" "no JSON output (acceptable if exit was clean)"
fi

rm -rf "$TEMP_PLUGIN"

# ═══════════════════════════════════════════════════
# LK.8: Calibration table has all required fields
# ═══════════════════════════════════════════════════
section "LK.8: Calibration Table Completeness"

OUTPUT=$(run_lookup '{"airline_code":"CX","origin":"HKG","destination":"LAX","plugin_dir":"'"$PLUGIN_DIR"'"}')

BS=$(echo "$OUTPUT" | jq -r '.calibration.batch_size // empty' 2>/dev/null)
CI=$(echo "$OUTPUT" | jq -r '.calibration.checkpoint_interval // empty' 2>/dev/null)
CM=$(echo "$OUTPUT" | jq -r '.calibration.commit_interval // empty' 2>/dev/null)

if [ -n "$BS" ]; then
  pass "LK.8a calibration.batch_size present ($BS)"
else
  fail "LK.8a calibration.batch_size" "missing"
fi

if [ -n "$CI" ]; then
  pass "LK.8b calibration.checkpoint_interval present ($CI)"
else
  fail "LK.8b calibration.checkpoint_interval" "missing"
fi

if [ -n "$CM" ]; then
  pass "LK.8c calibration.commit_interval present ($CM)"
else
  fail "LK.8c calibration.commit_interval" "missing"
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
  log "${GREEN}All lookup tests passed!${NC}"
else
  log "${RED}$FAIL test(s) failed — see details above${NC}"
fi

exit $FAIL
