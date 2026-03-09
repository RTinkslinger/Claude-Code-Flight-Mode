#!/bin/bash
# Flight Mode — Flight Input Parser
# Parses flight codes, airline+route strings, and natural language into structured data.
#
# Input: JSON on stdin  {"input": "CX884", "plugin_dir": "/path/to/plugin"}
#        or flight string as $1
# Output: JSON to stdout with parsed airline, route, and provider info

set -uo pipefail

# ---------------------------------------------------------------------------
# Resolve plugin directory and input
# ---------------------------------------------------------------------------
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-}"
FLIGHT_INPUT=""

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
  FLIGHT_INPUT=$(echo "$STDIN_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('input',''))" 2>/dev/null || true)
fi

# Fallback: $1 as flight string
if [ -z "$FLIGHT_INPUT" ] && [ "${1:-}" != "" ]; then
  FLIGHT_INPUT="$1"
fi

# Fallback: plugin dir from script location
if [ -z "$PLUGIN_DIR" ]; then
  PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi

AIRLINES_FILE="$PLUGIN_DIR/data/airline-codes.json"
AIRPORTS_FILE="$PLUGIN_DIR/data/airport-codes.json"

# ---------------------------------------------------------------------------
# Helper: emit JSON result
# ---------------------------------------------------------------------------
emit_result() {
  local airline_code="$1"
  local airline_name="$2"
  local origin="$3"
  local destination="$4"
  local origin_city="$5"
  local destination_city="$6"
  local provider="$7"
  local parsed_from="$8"
  local confidence="$9"
  local needs_route="${10}"

  # Build JSON with proper null handling
  local ac; [ "$airline_code" = "null" ] && ac="null" || ac="\"$airline_code\""
  local an; [ "$airline_name" = "null" ] && an="null" || an="\"$airline_name\""
  local og; [ "$origin" = "null" ] && og="null" || og="\"$origin\""
  local ds; [ "$destination" = "null" ] && ds="null" || ds="\"$destination\""
  local oc; [ "$origin_city" = "null" ] && oc="null" || oc="\"$origin_city\""
  local dc; [ "$destination_city" = "null" ] && dc="null" || dc="\"$destination_city\""
  local pv; [ "$provider" = "null" ] && pv="null" || pv="\"$provider\""
  local pf; [ "$parsed_from" = "null" ] && pf="null" || pf="\"$parsed_from\""

  cat <<EOJSON
{
  "airline_code": $ac,
  "airline_name": $an,
  "origin": $og,
  "destination": $ds,
  "origin_city": $oc,
  "destination_city": $dc,
  "provider": $pv,
  "parsed_from": "$parsed_from",
  "confidence": "$confidence",
  "needs_route": $needs_route
}
EOJSON
  exit 0
}

# ---------------------------------------------------------------------------
# No input — emit empty result
# ---------------------------------------------------------------------------
if [ -z "$FLIGHT_INPUT" ]; then
  emit_result "null" "null" "null" "null" "null" "null" "null" "null" "none" "false"
fi

# ---------------------------------------------------------------------------
# Check data files exist
# ---------------------------------------------------------------------------
if [ ! -f "$AIRLINES_FILE" ] || [ ! -f "$AIRPORTS_FILE" ]; then
  # Can't parse without data files — emit minimal result
  emit_result "null" "null" "null" "null" "null" "null" "null" "null" "none" "false"
fi

# ---------------------------------------------------------------------------
# All parsing is done in Python for robust regex + JSON handling
# ---------------------------------------------------------------------------
FLIGHT_INPUT_VAR="$FLIGHT_INPUT" \
AIRLINES_FILE_VAR="$AIRLINES_FILE" \
AIRPORTS_FILE_VAR="$AIRPORTS_FILE" \
python3 <<'PYEOF' && exit 0
import json
import re
import sys
import os

flight_input = os.environ.get("FLIGHT_INPUT_VAR", "")
airlines_file = os.environ.get("AIRLINES_FILE_VAR", "")
airports_file = os.environ.get("AIRPORTS_FILE_VAR", "")

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}

airlines = load_json(airlines_file)
airports = load_json(airports_file)

# Remove internal notes
airlines.pop("_note", None)
airports.pop("_note", None)

def lookup_airline_code(code):
    """Look up airline by IATA code (case-insensitive)."""
    code = code.upper()
    if code in airlines:
        info = airlines[code]
        return code, info["name"], info.get("provider", "unknown")
    return None, None, None

def lookup_airline_name(name):
    """Fuzzy match airline by name (case-insensitive partial match)."""
    name_lower = name.lower().strip()
    # Exact match first
    for code, info in airlines.items():
        if info["name"].lower() == name_lower:
            return code, info["name"], info.get("provider", "unknown")
    # Partial match — airline name starts with or contains the input
    for code, info in airlines.items():
        if name_lower in info["name"].lower() or info["name"].lower().startswith(name_lower):
            return code, info["name"], info.get("provider", "unknown")
    # Also try matching against the code itself
    for code, info in airlines.items():
        if code.lower() == name_lower:
            return code, info["name"], info.get("provider", "unknown")
    return None, None, None

def lookup_airport_code(code):
    """Look up airport by IATA code."""
    code = code.upper()
    if code in airports:
        info = airports[code]
        return code, info["city"]
    return None, None

def lookup_city_name(city):
    """Look up airport by city name (case-insensitive)."""
    city_lower = city.lower().strip()
    for code, info in airports.items():
        if info["city"].lower() == city_lower:
            return code, info["city"]
    # Partial match
    for code, info in airports.items():
        if city_lower in info["city"].lower() or info["city"].lower().startswith(city_lower):
            return code, info["city"]
    return None, None

def emit(airline_code, airline_name, origin, dest, origin_city, dest_city,
         provider, parsed_from, confidence, needs_route):
    result = {
        "airline_code": airline_code,
        "airline_name": airline_name,
        "origin": origin,
        "destination": dest,
        "origin_city": origin_city,
        "destination_city": dest_city,
        "provider": provider,
        "parsed_from": parsed_from,
        "confidence": confidence,
        "needs_route": needs_route
    }
    print(json.dumps(result, indent=2))
    sys.exit(0)

def emit_none():
    emit(None, None, None, None, None, None, None, None, "none", False)

# Normalize input
inp = flight_input.strip()
if not inp:
    emit_none()

# -----------------------------------------------------------------------
# Strategy 1: Flight code pattern — 2-3 letter code + digits
#   e.g. CX884, UA123, BA247, 6E2145, U2801, 5J312
#   IATA codes: 2 letters (CX), digit+letter (6E), letter+digit (U2),
#   or 3-letter ICAO (AAL). Try all known codes from the data file.
# -----------------------------------------------------------------------
# Try to match known airline codes at the start of the string
flight_code_parsed = False
for code in sorted(airlines.keys(), key=len, reverse=True):
    pattern = r'^(' + re.escape(code) + r')[\s-]?(\d{1,5})$'
    m = re.match(pattern, inp, re.IGNORECASE)
    if m:
        ac, an, pv = lookup_airline_code(m.group(1).upper())
        if ac:
            emit(ac, an, None, None, None, None, pv, "flight_code", "high", True)
            flight_code_parsed = True
            break

# Fallback: generic 2-letter code + digits (for codes not in our DB)
if not flight_code_parsed:
    flight_code_match = re.match(r'^([A-Z]{2})[\s-]?(\d{1,5})$', inp, re.IGNORECASE)
    if flight_code_match:
        code_part = flight_code_match.group(1).upper()
        # Not in our DB, but structurally valid
        emit(code_part, None, None, None, None, None, None, "flight_code", "low", True)

# -----------------------------------------------------------------------
# Strategy 2: Airline code/name + airport codes
#   e.g. "CX HKG-LAX", "CX HKG LAX", "Cathay Pacific HKG-LAX"
# -----------------------------------------------------------------------

# Pattern: CODE AIRPORT-AIRPORT or CODE AIRPORT AIRPORT
route_pattern = re.match(
    r'^([A-Z0-9]{2,3}|[A-Za-z][A-Za-z\s]+?)\s+([A-Z]{3})\s*[-–—/\s]\s*([A-Z]{3})$',
    inp, re.IGNORECASE
)
if route_pattern:
    airline_part = route_pattern.group(1).strip()
    apt1 = route_pattern.group(2).upper()
    apt2 = route_pattern.group(3).upper()

    # Try as code first, then as name
    ac, an, pv = lookup_airline_code(airline_part)
    if not ac:
        ac, an, pv = lookup_airline_name(airline_part)

    origin_code, origin_city = lookup_airport_code(apt1)
    dest_code, dest_city = lookup_airport_code(apt2)

    if ac and origin_code and dest_code:
        emit(ac, an, origin_code, dest_code, origin_city, dest_city, pv,
             "airline_route", "high", False)
    elif ac:
        # Airline matched but airports not in our DB — still useful
        emit(ac, an, apt1, apt2, None, None, pv, "airline_route", "medium", False)

# -----------------------------------------------------------------------
# Strategy 3: Airline name only (no route)
#   e.g. "Cathay Pacific", "United Airlines"
# -----------------------------------------------------------------------

# Check if entire input matches an airline name
ac, an, pv = lookup_airline_name(inp)
if ac:
    emit(ac, an, None, None, None, None, pv, "airline_name", "medium", True)

# -----------------------------------------------------------------------
# Strategy 4: Natural language — "cathay hong kong to los angeles"
#   Extract airline name and city names separated by "to", "-", "/", or spaces
# -----------------------------------------------------------------------

# Pattern: <airline> <city> to <city>
nl_match = re.match(
    r'^(.+?)\s+([\w\s]+?)\s+(?:to|->|→|-|–)\s+([\w\s]+)$',
    inp, re.IGNORECASE
)
if nl_match:
    airline_part = nl_match.group(1).strip()
    city1 = nl_match.group(2).strip()
    city2 = nl_match.group(3).strip()

    ac, an, pv = lookup_airline_code(airline_part)
    if not ac:
        ac, an, pv = lookup_airline_name(airline_part)

    origin_code, origin_city = lookup_city_name(city1)
    if not origin_code:
        origin_code, origin_city = lookup_airport_code(city1)

    dest_code, dest_city = lookup_city_name(city2)
    if not dest_code:
        dest_code, dest_city = lookup_airport_code(city2)

    if ac:
        confidence = "high" if (origin_code and dest_code) else "medium"
        needs = not (origin_code and dest_code)
        emit(ac, an, origin_code, dest_code, origin_city, dest_city, pv,
             "natural_language", confidence, needs)

# -----------------------------------------------------------------------
# Strategy 5: Just two airport codes — "HKG LAX" or "HKG-LAX"
# -----------------------------------------------------------------------
airports_only = re.match(r'^([A-Z]{3})\s*[-–—/\s]\s*([A-Z]{3})$', inp, re.IGNORECASE)
if airports_only:
    apt1 = airports_only.group(1).upper()
    apt2 = airports_only.group(2).upper()
    origin_code, origin_city = lookup_airport_code(apt1)
    dest_code, dest_city = lookup_airport_code(apt2)
    if origin_code or dest_code:
        emit(None, None, origin_code, dest_code, origin_city, dest_city, None,
             "route_only", "medium", False)

# -----------------------------------------------------------------------
# Strategy 6: Broad natural language — try splitting words to find an airline + cities
# -----------------------------------------------------------------------
words = inp.split()
if len(words) >= 2:
    # Try progressively longer airline name prefixes
    for split_at in range(1, min(len(words), 4)):
        airline_candidate = " ".join(words[:split_at])
        ac, an, pv = lookup_airline_name(airline_candidate)
        if ac:
            remaining = " ".join(words[split_at:])
            # Try to find cities or airport codes in remaining text
            # Look for "to" separator
            if " to " in remaining.lower():
                parts = re.split(r'\s+to\s+', remaining, flags=re.IGNORECASE)
                if len(parts) == 2:
                    city1, city2 = parts[0].strip(), parts[1].strip()
                    o_code, o_city = lookup_city_name(city1)
                    if not o_code:
                        o_code, o_city = lookup_airport_code(city1)
                    d_code, d_city = lookup_city_name(city2)
                    if not d_code:
                        d_code, d_city = lookup_airport_code(city2)
                    confidence = "high" if (o_code and d_code) else "medium"
                    needs = not (o_code and d_code)
                    emit(ac, an, o_code, d_code, o_city, d_city, pv,
                         "natural_language", confidence, needs)

            # Try airport code pairs in remaining
            apt_codes = re.findall(r'\b([A-Z]{3})\b', remaining.upper())
            if len(apt_codes) >= 2:
                o_code, o_city = lookup_airport_code(apt_codes[0])
                d_code, d_city = lookup_airport_code(apt_codes[1])
                if o_code and d_code:
                    emit(ac, an, o_code, d_code, o_city, d_city, pv,
                         "natural_language", "medium", False)

            # Just airline matched — no route
            emit(ac, an, None, None, None, None, pv, "airline_name", "low", True)

# Nothing matched
emit_none()
PYEOF

# If python3 fails entirely, emit a null result
emit_result "null" "null" "null" "null" "null" "null" "null" "null" "none" "false"
