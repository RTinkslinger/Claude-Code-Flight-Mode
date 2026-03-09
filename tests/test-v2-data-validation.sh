#!/bin/bash
# Flight Mode — V2 Test Suite: Data File Validation
# Validates all V2 data files for structural correctness and cross-references.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AIRLINES_FILE="$PLUGIN_DIR/data/airline-codes.json"
AIRPORTS_FILE="$PLUGIN_DIR/data/airport-codes.json"
CORRIDORS_FILE="$PLUGIN_DIR/data/route-corridors.json"
SSIDS_FILE="$PLUGIN_DIR/data/wifi-ssids.json"
EGRESS_FILE="$PLUGIN_DIR/data/provider-egress.json"
COUNTRIES_FILE="$PLUGIN_DIR/data/supported-countries.json"
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
# DV.1–DV.5: airline-codes.json
# ═══════════════════════════════════════════════════
section "DV.1–DV.5: airline-codes.json"

# DV.1: Valid JSON
if [ -f "$AIRLINES_FILE" ]; then
  if jq . "$AIRLINES_FILE" >/dev/null 2>&1; then
    pass "DV.1 airline-codes.json is valid JSON"
  else
    fail "DV.1 airline-codes.json" "invalid JSON"
  fi
else
  fail "DV.1 airline-codes.json exists" "file missing"
fi

# DV.2: Has 60+ entries (excluding _note)
AIRLINE_COUNT=$(jq '[keys[] | select(startswith("_") | not)] | length' "$AIRLINES_FILE" 2>/dev/null)
if [ -n "$AIRLINE_COUNT" ] && [ "$AIRLINE_COUNT" -ge 60 ] 2>/dev/null; then
  pass "DV.2 airline-codes.json has $AIRLINE_COUNT entries (>= 60)"
else
  fail "DV.2 airline count" "got $AIRLINE_COUNT, expected >= 60"
fi

# DV.3: Each airline has required fields (name, provider, country)
AIRLINES_FIELDS_OK=true
AIRLINES_CHECKED=0
for code in $(jq -r 'keys[] | select(startswith("_") | not)' "$AIRLINES_FILE" 2>/dev/null); do
  HAS_NAME=$(jq -r ".\"$code\" | has(\"name\")" "$AIRLINES_FILE" 2>/dev/null)
  HAS_PROV=$(jq -r ".\"$code\" | has(\"provider\")" "$AIRLINES_FILE" 2>/dev/null)
  HAS_CTRY=$(jq -r ".\"$code\" | has(\"country\")" "$AIRLINES_FILE" 2>/dev/null)
  if [ "$HAS_NAME" != "true" ] || [ "$HAS_PROV" != "true" ] || [ "$HAS_CTRY" != "true" ]; then
    AIRLINES_FIELDS_OK=false
    fail "DV.3 airline '$code'" "missing required fields (name/provider/country)"
    break
  fi
  AIRLINES_CHECKED=$((AIRLINES_CHECKED + 1))
done
if [ "$AIRLINES_FIELDS_OK" = "true" ]; then
  pass "DV.3 all $AIRLINES_CHECKED airlines have required fields (name, provider, country)"
fi

# DV.4: Provider values are one of the valid set
VALID_PROVIDERS="gogo inmarsat viasat panasonic starlink ses none unknown"
PROVIDERS_OK=true
for code in $(jq -r 'keys[] | select(startswith("_") | not)' "$AIRLINES_FILE" 2>/dev/null); do
  PROV=$(jq -r ".\"$code\".provider" "$AIRLINES_FILE" 2>/dev/null)
  if ! echo "$VALID_PROVIDERS" | grep -qw "$PROV"; then
    PROVIDERS_OK=false
    fail "DV.4 airline '$code' provider" "invalid value '$PROV'"
    break
  fi
done
if [ "$PROVIDERS_OK" = "true" ]; then
  pass "DV.4 all airline provider values are valid (gogo|inmarsat|viasat|panasonic|starlink|ses|none|unknown)"
fi

# DV.5: Known airlines present
KNOWN_AIRLINES=("AA" "DL" "UA" "CX" "EK" "SQ" "BA" "QF")
ALL_KNOWN_OK=true
for code in "${KNOWN_AIRLINES[@]}"; do
  if ! jq -e ".\"$code\"" "$AIRLINES_FILE" >/dev/null 2>&1; then
    ALL_KNOWN_OK=false
    fail "DV.5 known airline '$code'" "not found"
  fi
done
if [ "$ALL_KNOWN_OK" = "true" ]; then
  pass "DV.5 all known airlines present (${KNOWN_AIRLINES[*]})"
fi

# ═══════════════════════════════════════════════════
# DV.6–DV.11: airport-codes.json
# ═══════════════════════════════════════════════════
section "DV.6–DV.11: airport-codes.json"

# DV.6: Valid JSON
if [ -f "$AIRPORTS_FILE" ]; then
  if jq . "$AIRPORTS_FILE" >/dev/null 2>&1; then
    pass "DV.6 airport-codes.json is valid JSON"
  else
    fail "DV.6 airport-codes.json" "invalid JSON"
  fi
else
  fail "DV.6 airport-codes.json exists" "file missing"
fi

# DV.7: Has 90+ entries (excluding _note)
AIRPORT_COUNT=$(jq '[keys[] | select(startswith("_") | not)] | length' "$AIRPORTS_FILE" 2>/dev/null)
if [ -n "$AIRPORT_COUNT" ] && [ "$AIRPORT_COUNT" -ge 90 ] 2>/dev/null; then
  pass "DV.7 airport-codes.json has $AIRPORT_COUNT entries (>= 90)"
else
  fail "DV.7 airport count" "got $AIRPORT_COUNT, expected >= 90"
fi

# DV.8: Each airport has required fields (city, country, lat, lon)
AIRPORTS_FIELDS_OK=true
AIRPORTS_CHECKED=0
for code in $(jq -r 'keys[] | select(startswith("_") | not)' "$AIRPORTS_FILE" 2>/dev/null); do
  for field in "city" "country" "lat" "lon"; do
    HAS_FIELD=$(jq -r ".\"$code\" | has(\"$field\")" "$AIRPORTS_FILE" 2>/dev/null)
    if [ "$HAS_FIELD" != "true" ]; then
      AIRPORTS_FIELDS_OK=false
      fail "DV.8 airport '$code'" "missing field '$field'"
      break 2
    fi
  done
  AIRPORTS_CHECKED=$((AIRPORTS_CHECKED + 1))
done
if [ "$AIRPORTS_FIELDS_OK" = "true" ]; then
  pass "DV.8 all $AIRPORTS_CHECKED airports have required fields (city, country, lat, lon)"
fi

# DV.9: Latitude range valid (-90 to 90)
LAT_OK=true
for code in $(jq -r 'keys[] | select(startswith("_") | not)' "$AIRPORTS_FILE" 2>/dev/null); do
  LAT=$(jq -r ".\"$code\".lat" "$AIRPORTS_FILE" 2>/dev/null)
  VALID=$(python3 -c "print('ok' if -90 <= float('$LAT') <= 90 else 'bad')" 2>/dev/null)
  if [ "$VALID" != "ok" ]; then
    LAT_OK=false
    fail "DV.9 airport '$code' latitude" "out of range: $LAT"
    break
  fi
done
if [ "$LAT_OK" = "true" ]; then
  pass "DV.9 all airport latitudes within valid range (-90 to 90)"
fi

# DV.10: Longitude range valid (-180 to 180)
LON_OK=true
for code in $(jq -r 'keys[] | select(startswith("_") | not)' "$AIRPORTS_FILE" 2>/dev/null); do
  LON=$(jq -r ".\"$code\".lon" "$AIRPORTS_FILE" 2>/dev/null)
  VALID=$(python3 -c "print('ok' if -180 <= float('$LON') <= 180 else 'bad')" 2>/dev/null)
  if [ "$VALID" != "ok" ]; then
    LON_OK=false
    fail "DV.10 airport '$code' longitude" "out of range: $LON"
    break
  fi
done
if [ "$LON_OK" = "true" ]; then
  pass "DV.10 all airport longitudes within valid range (-180 to 180)"
fi

# DV.11: Known airports present
KNOWN_AIRPORTS=("JFK" "LAX" "LHR" "HKG" "SIN" "SYD" "NRT" "DXB")
ALL_AIRPORTS_KNOWN=true
for code in "${KNOWN_AIRPORTS[@]}"; do
  if ! jq -e ".\"$code\"" "$AIRPORTS_FILE" >/dev/null 2>&1; then
    ALL_AIRPORTS_KNOWN=false
    fail "DV.11 known airport '$code'" "not found"
  fi
done
if [ "$ALL_AIRPORTS_KNOWN" = "true" ]; then
  pass "DV.11 all known airports present (${KNOWN_AIRPORTS[*]})"
fi

# ═══════════════════════════════════════════════════
# DV.12–DV.20: route-corridors.json
# ═══════════════════════════════════════════════════
section "DV.12–DV.20: route-corridors.json"

# DV.12: Valid JSON
if [ -f "$CORRIDORS_FILE" ]; then
  if jq . "$CORRIDORS_FILE" >/dev/null 2>&1; then
    pass "DV.12 route-corridors.json is valid JSON"
  else
    fail "DV.12 route-corridors.json" "invalid JSON"
  fi
else
  fail "DV.12 route-corridors.json exists" "file missing"
fi

# DV.13: Has 10 corridors
CORRIDOR_COUNT=$(jq '.corridors | keys | length' "$CORRIDORS_FILE" 2>/dev/null)
if [ "$CORRIDOR_COUNT" = "10" ]; then
  pass "DV.13 route-corridors.json has $CORRIDOR_COUNT corridors"
else
  fail "DV.13 corridor count" "got $CORRIDOR_COUNT, expected 10"
fi

# DV.14: Each corridor has required fields
CORRIDOR_FIELDS_OK=true
for corridor in $(jq -r '.corridors | keys[]' "$CORRIDORS_FILE" 2>/dev/null); do
  for field in "name" "examples" "duration_hours" "peak_latitude" "waypoints"; do
    if ! jq -e ".corridors.\"$corridor\" | has(\"$field\")" "$CORRIDORS_FILE" >/dev/null 2>&1; then
      CORRIDOR_FIELDS_OK=false
      fail "DV.14 corridor '$corridor'" "missing field '$field'"
      break 2
    fi
  done
done
if [ "$CORRIDOR_FIELDS_OK" = "true" ]; then
  pass "DV.14 all corridors have required fields (name, examples, duration_hours, peak_latitude, waypoints)"
fi

# DV.15: Each waypoint has required fields (hour, lat, lon, signal, phase, note)
WP_FIELDS_OK=true
for corridor in $(jq -r '.corridors | keys[]' "$CORRIDORS_FILE" 2>/dev/null); do
  WP_COUNT=$(jq ".corridors.\"$corridor\".waypoints | length" "$CORRIDORS_FILE" 2>/dev/null)
  for i in $(seq 0 $((WP_COUNT - 1))); do
    for field in "hour" "lat" "lon" "signal" "phase" "note"; do
      if ! jq -e ".corridors.\"$corridor\".waypoints[$i] | has(\"$field\")" "$CORRIDORS_FILE" >/dev/null 2>&1; then
        WP_FIELDS_OK=false
        fail "DV.15 corridor '$corridor' waypoint $i" "missing field '$field'"
        break 3
      fi
    done
  done
done
if [ "$WP_FIELDS_OK" = "true" ]; then
  pass "DV.15 all waypoints have required fields (hour, lat, lon, signal, phase, note)"
fi

# DV.16: Signal values are 0-100
SIGNAL_OK=true
for corridor in $(jq -r '.corridors | keys[]' "$CORRIDORS_FILE" 2>/dev/null); do
  BAD_SIGNAL=$(jq ".corridors.\"$corridor\".waypoints[] | select(.signal < 0 or .signal > 100) | .signal" "$CORRIDORS_FILE" 2>/dev/null)
  if [ -n "$BAD_SIGNAL" ]; then
    SIGNAL_OK=false
    fail "DV.16 corridor '$corridor'" "signal out of range: $BAD_SIGNAL"
    break
  fi
done
if [ "$SIGNAL_OK" = "true" ]; then
  pass "DV.16 all waypoint signal values within 0-100"
fi

# DV.17: Waypoints are sorted by hour (ascending)
SORTED_OK=true
for corridor in $(jq -r '.corridors | keys[]' "$CORRIDORS_FILE" 2>/dev/null); do
  IS_SORTED=$(jq "
    .corridors.\"$corridor\".waypoints
    | [range(1; length)] | all(. as \$i |
        (.[\$i].hour >= .[(\$i - 1)].hour))
  " "$CORRIDORS_FILE" 2>/dev/null)
  # Alternate approach: check directly
  HOURS=$(jq -r ".corridors.\"$corridor\".waypoints[].hour" "$CORRIDORS_FILE" 2>/dev/null)
  PREV=-1
  SORT_VALID=true
  while IFS= read -r h; do
    COMPARE=$(python3 -c "print('ok' if float('$h') >= float('$PREV') else 'bad')" 2>/dev/null)
    if [ "$COMPARE" = "bad" ]; then
      SORT_VALID=false
      break
    fi
    PREV="$h"
  done <<< "$HOURS"
  if [ "$SORT_VALID" = "false" ]; then
    SORTED_OK=false
    fail "DV.17 corridor '$corridor'" "waypoints not sorted by hour"
    break
  fi
done
if [ "$SORTED_OK" = "true" ]; then
  pass "DV.17 all corridors have waypoints sorted by hour (ascending)"
fi

# DV.18: First waypoint of each corridor has signal=0 and phase="departure"
FIRST_WP_OK=true
for corridor in $(jq -r '.corridors | keys[]' "$CORRIDORS_FILE" 2>/dev/null); do
  FIRST_SIGNAL=$(jq ".corridors.\"$corridor\".waypoints[0].signal" "$CORRIDORS_FILE" 2>/dev/null)
  FIRST_PHASE=$(jq -r ".corridors.\"$corridor\".waypoints[0].phase" "$CORRIDORS_FILE" 2>/dev/null)
  if [ "$FIRST_SIGNAL" != "0" ] || [ "$FIRST_PHASE" != "departure" ]; then
    FIRST_WP_OK=false
    fail "DV.18 corridor '$corridor' first waypoint" "signal=$FIRST_SIGNAL phase=$FIRST_PHASE (expected 0, departure)"
    break
  fi
done
if [ "$FIRST_WP_OK" = "true" ]; then
  pass "DV.18 all corridors start with signal=0, phase=departure"
fi

# DV.19: Last waypoint of each corridor has signal=0 and phase="landing"
LAST_WP_OK=true
for corridor in $(jq -r '.corridors | keys[]' "$CORRIDORS_FILE" 2>/dev/null); do
  LAST_SIGNAL=$(jq ".corridors.\"$corridor\".waypoints[-1].signal" "$CORRIDORS_FILE" 2>/dev/null)
  LAST_PHASE=$(jq -r ".corridors.\"$corridor\".waypoints[-1].phase" "$CORRIDORS_FILE" 2>/dev/null)
  if [ "$LAST_SIGNAL" != "0" ] || [ "$LAST_PHASE" != "landing" ]; then
    LAST_WP_OK=false
    fail "DV.19 corridor '$corridor' last waypoint" "signal=$LAST_SIGNAL phase=$LAST_PHASE (expected 0, landing)"
    break
  fi
done
if [ "$LAST_WP_OK" = "true" ]; then
  pass "DV.19 all corridors end with signal=0, phase=landing"
fi

# DV.20: Total waypoints across all corridors >= 100
TOTAL_WP=$(jq '[.corridors[].waypoints | length] | add' "$CORRIDORS_FILE" 2>/dev/null)
if [ -n "$TOTAL_WP" ] && [ "$TOTAL_WP" -ge 100 ] 2>/dev/null; then
  pass "DV.20 total waypoints across all corridors = $TOTAL_WP (>= 100)"
else
  fail "DV.20 total waypoints" "got $TOTAL_WP, expected >= 100"
fi

# ═══════════════════════════════════════════════════
# DV.21–DV.23: Other Data Files Valid JSON
# ═══════════════════════════════════════════════════
section "DV.21–DV.23: Other Data Files"

# DV.21: wifi-ssids.json is valid JSON
if [ -f "$SSIDS_FILE" ] && jq . "$SSIDS_FILE" >/dev/null 2>&1; then
  pass "DV.21 wifi-ssids.json is valid JSON"
else
  fail "DV.21 wifi-ssids.json" "missing or invalid JSON"
fi

# DV.22: provider-egress.json is valid JSON
if [ -f "$EGRESS_FILE" ] && jq . "$EGRESS_FILE" >/dev/null 2>&1; then
  pass "DV.22 provider-egress.json is valid JSON"
else
  fail "DV.22 provider-egress.json" "missing or invalid JSON"
fi

# DV.23: supported-countries.json is valid JSON
if [ -f "$COUNTRIES_FILE" ] && jq . "$COUNTRIES_FILE" >/dev/null 2>&1; then
  pass "DV.23 supported-countries.json is valid JSON"
else
  fail "DV.23 supported-countries.json" "missing or invalid JSON"
fi

# ═══════════════════════════════════════════════════
# DV.24–DV.25: Cross-Reference Validation
# ═══════════════════════════════════════════════════
section "DV.24–DV.25: Cross-Reference Validation"

# DV.24: All airline country codes exist in airport-codes.json country codes or supported-countries.json
# Build a set of all known country codes from airports + supported countries
KNOWN_COUNTRIES=$(python3 -c "
import json
with open('$AIRPORTS_FILE') as f:
    airports = json.load(f)
with open('$COUNTRIES_FILE') as f:
    countries = json.load(f)

airport_countries = set()
for code, info in airports.items():
    if code.startswith('_'): continue
    airport_countries.add(info.get('country', ''))

all_countries = airport_countries | set(countries.get('supported', [])) | set(countries.get('explicitly_excluded', []))

with open('$AIRLINES_FILE') as f:
    airlines = json.load(f)

missing = []
for code, info in airlines.items():
    if code.startswith('_'): continue
    country = info.get('country', '')
    if country and country not in all_countries:
        missing.append(f'{code}={country}')

if missing:
    print('MISSING:' + ','.join(missing))
else:
    print('OK')
" 2>/dev/null)

if [ "$KNOWN_COUNTRIES" = "OK" ]; then
  pass "DV.24 all airline country codes found in airports/countries data"
else
  fail "DV.24 airline country cross-reference" "$KNOWN_COUNTRIES"
fi

# DV.25: Corridor examples reference valid airport codes from airport-codes.json
CORRIDOR_REFS=$(python3 -c "
import json, re
with open('$CORRIDORS_FILE') as f:
    corridors = json.load(f)
with open('$AIRPORTS_FILE') as f:
    airports = json.load(f)

airport_keys = set(k for k in airports if not k.startswith('_'))

missing = []
for cname, cdata in corridors.get('corridors', {}).items():
    for example in cdata.get('examples', []):
        codes = re.findall(r'[A-Z]{3}', example)
        for c in codes:
            if c not in airport_keys:
                missing.append(f'{cname}:{example}:{c}')

if missing:
    print('MISSING:' + ','.join(missing[:5]))
else:
    print('OK')
" 2>/dev/null)

if [ "$CORRIDOR_REFS" = "OK" ]; then
  pass "DV.25 all corridor example airport codes exist in airport-codes.json"
else
  fail "DV.25 corridor airport cross-reference" "$CORRIDOR_REFS"
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
  log "${GREEN}All data validation tests passed!${NC}"
else
  log "${RED}$FAIL test(s) failed — see details above${NC}"
fi

exit $FAIL
