#!/bin/bash
# Flight Mode — V2 Test Suite: flight-on-activate.sh
# Tests FLIGHT_MODE.md + .flight-state.md creation, field content,
# weak zone conditionals, and minimal input resilience
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$PLUGIN_DIR/scripts/flight-on-activate.sh"
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

# Helper: run activate with given JSON
run_activate() {
  local json="$1"
  echo "$json" | bash "$SCRIPT" 2>/dev/null
}

# ═══════════════════════════════════════════════════
# Prerequisites
# ═══════════════════════════════════════════════════
section "AC.0: Prerequisites"

if [ ! -f "$SCRIPT" ]; then
  fail "AC.0a flight-on-activate.sh exists" "file missing at $SCRIPT"
  log ""
  log "Cannot continue without flight-on-activate.sh"
  exit 1
fi

if [ ! -x "$SCRIPT" ]; then
  fail "AC.0b flight-on-activate.sh is executable" "not executable"
else
  pass "AC.0b flight-on-activate.sh is executable"
fi

if ! command -v jq >/dev/null 2>&1; then
  fail "AC.0c jq is installed" "jq not found — cannot run tests"
  exit 1
fi
pass "AC.0c jq is installed"

# ═══════════════════════════════════════════════════
# AC.1: Basic activation creates both files
# ═══════════════════════════════════════════════════
section "AC.1: Basic Activation"

TEMP_DIR=$(mktemp -d)

INPUT_JSON='{"airline_code":"CX","airline_name":"Cathay Pacific","origin":"HKG","destination":"LAX","provider":"viasat","rating":"USABLE","stable_window":"20-40","duration_hours":12,"api_verdict":"GO","egress_country":"US","dashboard_url":"http://localhost:8234","calibration":{"batch_size":"1-2","checkpoint_interval":"2-3","commit_interval":"2-3"},"cwd":"'"$TEMP_DIR"'"}'

OUTPUT=$(run_activate "$INPUT_JSON")

if [ -f "$TEMP_DIR/FLIGHT_MODE.md" ]; then
  pass "AC.1a FLIGHT_MODE.md created"
else
  fail "AC.1a FLIGHT_MODE.md created" "file not found"
fi

if [ -f "$TEMP_DIR/.flight-state.md" ]; then
  pass "AC.1b .flight-state.md created"
else
  fail "AC.1b .flight-state.md created" "file not found"
fi

# Check output JSON
STATUS=$(echo "$OUTPUT" | jq -r '.status // empty' 2>/dev/null)
if [ "$STATUS" = "activated" ]; then
  pass "AC.1c output JSON has status=activated"
else
  fail "AC.1c output status" "expected activated, got: $STATUS (output: $OUTPUT)"
fi

# ═══════════════════════════════════════════════════
# AC.2: FLIGHT_MODE.md contains correct fields
# ═══════════════════════════════════════════════════
section "AC.2: FLIGHT_MODE.md Content"

FM_FILE="$TEMP_DIR/FLIGHT_MODE.md"
if [ -f "$FM_FILE" ]; then
  FM_CONTENT=$(cat "$FM_FILE")

  if echo "$FM_CONTENT" | grep -q "Cathay Pacific CX"; then
    pass "AC.2a contains 'Cathay Pacific CX'"
  else
    fail "AC.2a 'Cathay Pacific CX'" "not found in FLIGHT_MODE.md"
  fi

  if echo "$FM_CONTENT" | grep -q "HKG -> LAX"; then
    pass "AC.2b contains 'HKG -> LAX'"
  else
    fail "AC.2b 'HKG -> LAX'" "not found in FLIGHT_MODE.md"
  fi

  if echo "$FM_CONTENT" | grep -q "USABLE"; then
    pass "AC.2c contains 'USABLE'"
  else
    fail "AC.2c 'USABLE'" "not found in FLIGHT_MODE.md"
  fi

  if echo "$FM_CONTENT" | grep -q "viasat"; then
    pass "AC.2d contains 'viasat'"
  else
    fail "AC.2d 'viasat'" "not found in FLIGHT_MODE.md"
  fi

  if echo "$FM_CONTENT" | grep -q "Condensed Protocol"; then
    pass "AC.2e contains 'Condensed Protocol'"
  else
    fail "AC.2e 'Condensed Protocol'" "not found in FLIGHT_MODE.md"
  fi
else
  fail "AC.2 FLIGHT_MODE.md" "file not created (skipping content checks)"
fi

# ═══════════════════════════════════════════════════
# AC.3: .flight-state.md contains correct fields
# ═══════════════════════════════════════════════════
section "AC.3: .flight-state.md Content"

FS_FILE="$TEMP_DIR/.flight-state.md"
if [ -f "$FS_FILE" ]; then
  FS_CONTENT=$(cat "$FS_FILE")

  if echo "$FS_CONTENT" | grep -q "Cathay Pacific CX HKG-LAX"; then
    pass "AC.3a contains 'Cathay Pacific CX HKG-LAX'"
  else
    fail "AC.3a 'Cathay Pacific CX HKG-LAX'" "not found in .flight-state.md"
  fi

  if echo "$FS_CONTENT" | grep -q "USABLE"; then
    pass "AC.3b contains 'USABLE'"
  else
    fail "AC.3b 'USABLE'" "not found in .flight-state.md"
  fi

  if echo "$FS_CONTENT" | grep -q "awaiting user input"; then
    pass "AC.3c contains 'awaiting user input'"
  else
    fail "AC.3c 'awaiting user input'" "not found in .flight-state.md"
  fi
else
  fail "AC.3 .flight-state.md" "file not created (skipping content checks)"
fi

rm -rf "$TEMP_DIR"

# ═══════════════════════════════════════════════════
# AC.4: Weak zone conditional — included when present
# ═══════════════════════════════════════════════════
section "AC.4: Weak Zone — Present"

TEMP_DIR=$(mktemp -d)

INPUT_WZ='{"airline_code":"CX","airline_name":"Cathay Pacific","origin":"HKG","destination":"LAX","provider":"gogo","rating":"USABLE","stable_window":"20-40","duration_hours":13,"api_verdict":"GO","egress_country":"US","dashboard_url":"http://localhost:8234","calibration":{"batch_size":"1-2","checkpoint_interval":"2-3","commit_interval":"2-3"},"weak_zone":{"start_hour":4,"end_hour":8,"reason":"mid-Pacific"},"cwd":"'"$TEMP_DIR"'"}'

run_activate "$INPUT_WZ" >/dev/null

FM_FILE="$TEMP_DIR/FLIGHT_MODE.md"
if [ -f "$FM_FILE" ]; then
  FM_CONTENT=$(cat "$FM_FILE")

  if echo "$FM_CONTENT" | grep -q "Weak Zone"; then
    pass "AC.4a FLIGHT_MODE.md contains 'Weak Zone'"
  else
    fail "AC.4a 'Weak Zone'" "not found in FLIGHT_MODE.md"
  fi

  if echo "$FM_CONTENT" | grep -q "Hours 4-8"; then
    pass "AC.4b FLIGHT_MODE.md contains 'Hours 4-8'"
  else
    fail "AC.4b 'Hours 4-8'" "not found in FLIGHT_MODE.md"
  fi
else
  fail "AC.4 FLIGHT_MODE.md" "file not created"
fi

rm -rf "$TEMP_DIR"

# ═══════════════════════════════════════════════════
# AC.5: Weak zone conditional — excluded when absent
# ═══════════════════════════════════════════════════
section "AC.5: Weak Zone — Absent"

TEMP_DIR=$(mktemp -d)

INPUT_NOWZ='{"airline_code":"DL","airline_name":"Delta","origin":"JFK","destination":"LAX","provider":"gogo","rating":"GOOD","stable_window":"45-90","duration_hours":5,"api_verdict":"GO","egress_country":"US","dashboard_url":"http://localhost:8234","calibration":{"batch_size":"up to 3","checkpoint_interval":"3-4","commit_interval":"3-4"},"cwd":"'"$TEMP_DIR"'"}'

run_activate "$INPUT_NOWZ" >/dev/null

FM_FILE="$TEMP_DIR/FLIGHT_MODE.md"
if [ -f "$FM_FILE" ]; then
  FM_CONTENT=$(cat "$FM_FILE")

  if echo "$FM_CONTENT" | grep -q "Weak Zone"; then
    fail "AC.5 'Weak Zone' absent" "found 'Weak Zone' in FLIGHT_MODE.md but no weak_zone was provided"
  else
    pass "AC.5 FLIGHT_MODE.md does NOT contain 'Weak Zone' when none provided"
  fi
else
  fail "AC.5 FLIGHT_MODE.md" "file not created"
fi

rm -rf "$TEMP_DIR"

# ═══════════════════════════════════════════════════
# AC.6: Minimal input (missing optional fields)
# ═══════════════════════════════════════════════════
section "AC.6: Minimal Input"

TEMP_DIR=$(mktemp -d)

INPUT_MIN='{"cwd":"'"$TEMP_DIR"'"}'

OUTPUT=$(run_activate "$INPUT_MIN")
RC=$?

if [ $RC -eq 0 ]; then
  pass "AC.6a no crash with minimal input (exit 0)"
else
  fail "AC.6a no crash" "exit code $RC"
fi

if [ -f "$TEMP_DIR/FLIGHT_MODE.md" ]; then
  pass "AC.6b FLIGHT_MODE.md created with minimal input"
else
  fail "AC.6b FLIGHT_MODE.md" "not created"
fi

if [ -f "$TEMP_DIR/.flight-state.md" ]; then
  pass "AC.6c .flight-state.md created with minimal input"
else
  fail "AC.6c .flight-state.md" "not created"
fi

# Verify defaults were used (should show ?? for code, Unknown for name)
if [ -f "$TEMP_DIR/FLIGHT_MODE.md" ]; then
  FM_CONTENT=$(cat "$TEMP_DIR/FLIGHT_MODE.md")
  if echo "$FM_CONTENT" | grep -q "??"; then
    pass "AC.6d uses default values for missing fields (found ?? placeholders)"
  else
    # Might use 'Unknown' instead — either is acceptable
    if echo "$FM_CONTENT" | grep -q "Unknown"; then
      pass "AC.6d uses default values for missing fields (found Unknown placeholder)"
    else
      fail "AC.6d default values" "no placeholder defaults found"
    fi
  fi
fi

rm -rf "$TEMP_DIR"

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
  log "${GREEN}All activate tests passed!${NC}"
else
  log "${RED}$FAIL test(s) failed — see details above${NC}"
fi

exit $FAIL
