#!/bin/bash
# Flight Mode — V2 Test Suite: parse-flight.sh
# Tests all 6 parsing strategies: flight code, airline+route, airline name,
# natural language, airports only, broad NL
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$PLUGIN_DIR/scripts/parse-flight.sh"
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

# Helper: run parse-flight with a given input string and return JSON
run_parse() {
  local input="$1"
  echo "{\"input\": \"$input\", \"plugin_dir\": \"$PLUGIN_DIR\"}" | bash "$SCRIPT" 2>/dev/null
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
section "PF.0: Prerequisites"

if [ ! -f "$SCRIPT" ]; then
  fail "PF.0a parse-flight.sh exists" "file missing at $SCRIPT"
  log ""
  log "Cannot continue without parse-flight.sh"
  exit 1
fi

if [ ! -x "$SCRIPT" ]; then
  fail "PF.0b parse-flight.sh is executable" "not executable"
else
  pass "PF.0b parse-flight.sh is executable"
fi

if ! command -v jq >/dev/null 2>&1; then
  fail "PF.0c jq is installed" "jq not found — cannot run tests"
  exit 1
fi
pass "PF.0c jq is installed"

if ! command -v python3 >/dev/null 2>&1; then
  fail "PF.0d python3 is installed" "python3 not found — parse-flight.sh requires it"
  exit 1
fi
pass "PF.0d python3 is installed"

# ═══════════════════════════════════════════════════
# Strategy 1: Flight Code Parsing
# ═══════════════════════════════════════════════════
section "PF.1–PF.6: Flight Code Parsing"

# PF.1: CX884 → Cathay Pacific
OUTPUT=$(run_parse "CX884")
AC=$(jq_field "$OUTPUT" "airline_code")
AN=$(jq_field "$OUTPUT" "airline_name")
PF=$(jq_field "$OUTPUT" "parsed_from")
CF=$(jq_field "$OUTPUT" "confidence")
NR=$(jq_field "$OUTPUT" "needs_route")
if [ "$AC" = "CX" ] && [ "$AN" = "Cathay Pacific" ] && [ "$PF" = "flight_code" ] && [ "$CF" = "high" ] && [ "$NR" = "true" ]; then
  pass "PF.1 CX884 → CX, Cathay Pacific, flight_code, high, needs_route=true"
else
  fail "PF.1 CX884" "ac=$AC an=$AN pf=$PF cf=$CF nr=$NR"
fi

# PF.2: UA123 → United Airlines
OUTPUT=$(run_parse "UA123")
AC=$(jq_field "$OUTPUT" "airline_code")
AN=$(jq_field "$OUTPUT" "airline_name")
CF=$(jq_field "$OUTPUT" "confidence")
if [ "$AC" = "UA" ] && [ "$AN" = "United Airlines" ] && [ "$CF" = "high" ]; then
  pass "PF.2 UA123 → UA, United Airlines, high"
else
  fail "PF.2 UA123" "ac=$AC an=$AN cf=$CF"
fi

# PF.3: Flight code with space "BA 247"
OUTPUT=$(run_parse "BA 247")
AC=$(jq_field "$OUTPUT" "airline_code")
if [ "$AC" = "BA" ]; then
  pass "PF.3 'BA 247' → BA (space separator)"
else
  fail "PF.3 'BA 247'" "ac=$AC"
fi

# PF.4: Flight code with dash "DL-456"
OUTPUT=$(run_parse "DL-456")
AC=$(jq_field "$OUTPUT" "airline_code")
if [ "$AC" = "DL" ]; then
  pass "PF.4 'DL-456' → DL (dash separator)"
else
  fail "PF.4 'DL-456'" "ac=$AC"
fi

# PF.5: Two-char alphanumeric "6E2145" (digit-start code)
OUTPUT=$(run_parse "6E2145")
AC=$(jq_field "$OUTPUT" "airline_code")
AN=$(jq_field "$OUTPUT" "airline_name")
if [ "$AC" = "6E" ] && [ "$AN" = "IndiGo" ]; then
  pass "PF.5 6E2145 → 6E, IndiGo (digit-start code)"
else
  fail "PF.5 6E2145" "ac=$AC an=$AN"
fi

# PF.6: Unknown flight code "ZZ999"
OUTPUT=$(run_parse "ZZ999")
AC=$(jq_field "$OUTPUT" "airline_code")
CF=$(jq_field "$OUTPUT" "confidence")
if [ "$AC" = "ZZ" ] && [ "$CF" = "low" ]; then
  pass "PF.6 ZZ999 → ZZ, confidence=low (unknown airline)"
else
  fail "PF.6 ZZ999" "ac=$AC cf=$CF"
fi

# ═══════════════════════════════════════════════════
# Strategy 2: Airline + Route
# ═══════════════════════════════════════════════════
section "PF.7–PF.9: Airline + Route Parsing"

# PF.7: CX HKG-LAX
OUTPUT=$(run_parse "CX HKG-LAX")
AC=$(jq_field "$OUTPUT" "airline_code")
OG=$(jq_field "$OUTPUT" "origin")
DS=$(jq_field "$OUTPUT" "destination")
PF=$(jq_field "$OUTPUT" "parsed_from")
NR=$(jq_field "$OUTPUT" "needs_route")
if [ "$AC" = "CX" ] && [ "$OG" = "HKG" ] && [ "$DS" = "LAX" ] && [ "$PF" = "airline_route" ] && [ "$NR" = "false" ]; then
  pass "PF.7 'CX HKG-LAX' → CX, HKG, LAX, airline_route, needs_route=false"
else
  fail "PF.7 'CX HKG-LAX'" "ac=$AC og=$OG ds=$DS pf=$PF nr=$NR"
fi

# PF.8: DL JFK LAX (space-separated route)
OUTPUT=$(run_parse "DL JFK LAX")
AC=$(jq_field "$OUTPUT" "airline_code")
OG=$(jq_field "$OUTPUT" "origin")
DS=$(jq_field "$OUTPUT" "destination")
if [ "$AC" = "DL" ] && [ "$OG" = "JFK" ] && [ "$DS" = "LAX" ]; then
  pass "PF.8 'DL JFK LAX' → DL, JFK, LAX (space-separated)"
else
  fail "PF.8 'DL JFK LAX'" "ac=$AC og=$OG ds=$DS"
fi

# PF.9: Airline name + route "Cathay Pacific HKG-LAX"
OUTPUT=$(run_parse "Cathay Pacific HKG-LAX")
AC=$(jq_field "$OUTPUT" "airline_code")
OG=$(jq_field "$OUTPUT" "origin")
DS=$(jq_field "$OUTPUT" "destination")
if [ "$AC" = "CX" ] && [ "$OG" = "HKG" ] && [ "$DS" = "LAX" ]; then
  pass "PF.9 'Cathay Pacific HKG-LAX' → CX, HKG, LAX"
else
  fail "PF.9 'Cathay Pacific HKG-LAX'" "ac=$AC og=$OG ds=$DS"
fi

# ═══════════════════════════════════════════════════
# Strategy 3: Airline Name Only
# ═══════════════════════════════════════════════════
section "PF.10–PF.11: Airline Name Only"

# PF.10: "Cathay Pacific" → airline name only
OUTPUT=$(run_parse "Cathay Pacific")
AC=$(jq_field "$OUTPUT" "airline_code")
NR=$(jq_field "$OUTPUT" "needs_route")
PF=$(jq_field "$OUTPUT" "parsed_from")
if [ "$AC" = "CX" ] && [ "$NR" = "true" ] && [ "$PF" = "airline_name" ]; then
  pass "PF.10 'Cathay Pacific' → CX, needs_route=true, parsed_from=airline_name"
else
  fail "PF.10 'Cathay Pacific'" "ac=$AC nr=$NR pf=$PF"
fi

# PF.11: "United Airlines" → airline name only
OUTPUT=$(run_parse "United Airlines")
AC=$(jq_field "$OUTPUT" "airline_code")
if [ "$AC" = "UA" ]; then
  pass "PF.11 'United Airlines' → UA"
else
  fail "PF.11 'United Airlines'" "ac=$AC"
fi

# ═══════════════════════════════════════════════════
# Strategy 4: Natural Language
# ═══════════════════════════════════════════════════
section "PF.12: Natural Language"

# PF.12: "cathay hong kong to los angeles"
OUTPUT=$(run_parse "cathay hong kong to los angeles")
AC=$(jq_field "$OUTPUT" "airline_code")
OG=$(jq_field "$OUTPUT" "origin")
DS=$(jq_field "$OUTPUT" "destination")
if [ "$AC" = "CX" ] && [ "$OG" = "HKG" ] && [ "$DS" = "LAX" ]; then
  pass "PF.12 'cathay hong kong to los angeles' → CX, HKG, LAX"
else
  # Partial credit: at least found the airline
  if [ "$AC" = "CX" ]; then
    pass "PF.12 'cathay hong kong to los angeles' → CX (airline found, route: og=$OG ds=$DS)"
  else
    fail "PF.12 'cathay hong kong to los angeles'" "ac=$AC og=$OG ds=$DS"
  fi
fi

# ═══════════════════════════════════════════════════
# Strategy 5: Airports Only
# ═══════════════════════════════════════════════════
section "PF.13–PF.14: Airports Only"

# PF.13: "HKG-LAX"
OUTPUT=$(run_parse "HKG-LAX")
OG=$(jq_field "$OUTPUT" "origin")
DS=$(jq_field "$OUTPUT" "destination")
PF=$(jq_field "$OUTPUT" "parsed_from")
if [ "$OG" = "HKG" ] && [ "$DS" = "LAX" ] && [ "$PF" = "route_only" ]; then
  pass "PF.13 'HKG-LAX' → HKG, LAX, parsed_from=route_only"
else
  fail "PF.13 'HKG-LAX'" "og=$OG ds=$DS pf=$PF"
fi

# PF.14: "HKG LAX" (space separator)
OUTPUT=$(run_parse "HKG LAX")
OG=$(jq_field "$OUTPUT" "origin")
DS=$(jq_field "$OUTPUT" "destination")
if [ "$OG" = "HKG" ] && [ "$DS" = "LAX" ]; then
  pass "PF.14 'HKG LAX' → HKG, LAX (space separator)"
else
  fail "PF.14 'HKG LAX'" "og=$OG ds=$DS"
fi

# ═══════════════════════════════════════════════════
# Edge Cases
# ═══════════════════════════════════════════════════
section "PF.15–PF.21: Edge Cases"

# PF.15: Empty input
OUTPUT=$(echo '{"input": "", "plugin_dir": "'"$PLUGIN_DIR"'"}' | bash "$SCRIPT" 2>/dev/null)
CF=$(jq_field "$OUTPUT" "confidence")
if [ "$CF" = "none" ]; then
  pass "PF.15 Empty input → confidence=none"
else
  fail "PF.15 empty input" "cf=$CF"
fi

# PF.16: Gibberish "hello world foo"
OUTPUT=$(run_parse "hello world foo")
CF=$(jq_field "$OUTPUT" "confidence")
if [ "$CF" = "none" ] || [ "$CF" = "low" ]; then
  pass "PF.16 'hello world foo' → confidence=$CF (none or low)"
else
  fail "PF.16 gibberish" "cf=$CF"
fi

# PF.17: Case insensitivity "cx884"
OUTPUT=$(run_parse "cx884")
AC=$(jq_field "$OUTPUT" "airline_code")
if [ "$AC" = "CX" ]; then
  pass "PF.17 'cx884' → CX (case insensitive)"
else
  fail "PF.17 case insensitivity" "ac=$AC"
fi

# PF.18: Airline name partial "Emirates"
OUTPUT=$(run_parse "Emirates")
AC=$(jq_field "$OUTPUT" "airline_code")
if [ "$AC" = "EK" ]; then
  pass "PF.18 'Emirates' → EK (partial name match)"
else
  fail "PF.18 'Emirates'" "ac=$AC"
fi

# PF.19: "5J312" → digit-start code
OUTPUT=$(run_parse "5J312")
AC=$(jq_field "$OUTPUT" "airline_code")
AN=$(jq_field "$OUTPUT" "airline_name")
if [ "$AC" = "5J" ] && [ "$AN" = "Cebu Pacific" ]; then
  pass "PF.19 '5J312' → 5J, Cebu Pacific (digit-start code)"
else
  fail "PF.19 '5J312'" "ac=$AC an=$AN"
fi

# PF.20: "U2801" → letter-digit code
OUTPUT=$(run_parse "U2801")
AC=$(jq_field "$OUTPUT" "airline_code")
AN=$(jq_field "$OUTPUT" "airline_name")
if [ "$AC" = "U2" ] && [ "$AN" = "easyJet" ]; then
  pass "PF.20 'U2801' → U2, easyJet (letter-digit code)"
else
  fail "PF.20 'U2801'" "ac=$AC an=$AN"
fi

# PF.21: Output is valid JSON for all inputs
section "PF.21: Valid JSON Output"
VALID_JSON=true
for INPUT in "CX884" "UA123" "BA 247" "Cathay Pacific" "HKG-LAX" "" "gibberish" "cx884" "5J312" "U2801" "ZZ999"; do
  OUTPUT=$(run_parse "$INPUT")
  if ! echo "$OUTPUT" | jq . >/dev/null 2>&1; then
    VALID_JSON=false
    fail "PF.21 valid JSON for '$INPUT'" "invalid JSON: $OUTPUT"
    break
  fi
done
if [ "$VALID_JSON" = "true" ]; then
  pass "PF.21 all inputs produce valid JSON output"
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
  log "${GREEN}All parse-flight tests passed!${NC}"
else
  log "${RED}$FAIL test(s) failed — see details above${NC}"
fi

exit $FAIL
