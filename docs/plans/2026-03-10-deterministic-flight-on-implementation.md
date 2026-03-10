# Deterministic Flight-On Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the LLM-interpreted flight-on skill with a two-phase orchestrator that runs scripts deterministically via `!`command`` injection, reducing Claude's role to presentation + confirmation.

**Architecture:** Three new scripts (preflight orchestrator, lookup, activate) called in sequence. Preflight runs at skill load via `!`command`` — deterministic. Lookup and activate are single bash calls Claude makes only when needed. A safety hook blocks direct FLIGHT_MODE.md writes.

**Tech Stack:** Bash orchestration, Python for JSON/data operations, jq for JSON manipulation.

---

### Task 1: Create `data/airline-profiles.json`

**Files:**
- Create: `data/airline-profiles.json`

**Step 1: Write the data file**

Create `data/airline-profiles.json` — a JSON mirror of the Quick Lookup Table in `data/flight-profiles.md`. Every row in the markdown table becomes a keyed entry. Airlines that share a code but have variant rows (e.g., "United (Starlink)" vs "United (legacy GEO)") use the primary IATA code with the better-documented variant as default. The lookup script will use provider to disambiguate when needed.

Map from `data/airline-codes.json` IATA codes → profile data extracted from the markdown table. Include all airlines from both files. Airlines in `airline-codes.json` but not in the profiles table get the `"default"` profile.

```json
{
  "_note": "Programmatic mirror of flight-profiles.md Quick Lookup Table. Used by flight-on-lookup.sh.",
  "profiles": {
    "DL": {"name": "Delta", "rating_domestic": "GOOD", "rating_longhaul": "USABLE", "stable_window_domestic": "45-90", "stable_window_longhaul": "20-40", "note": "Upload <1 Mbps; free for SkyMiles"},
    "UA": {"name": "United Airlines", "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "Mainline transitioning to LEO; check aircraft type"},
    "AA": {"name": "American Airlines", "rating_domestic": "USABLE", "rating_longhaul": "CHOPPY", "stable_window_domestic": "15-30", "stable_window_longhaul": "15-30", "note": "Re-auth after device sleep; widebody uses Panasonic"},
    "B6": {"name": "JetBlue", "rating_domestic": "GOOD", "rating_longhaul": "GOOD", "stable_window_domestic": "30-60", "stable_window_longhaul": "30-60", "note": "Free for all passengers"},
    "WN": {"name": "Southwest Airlines", "rating_domestic": "CHOPPY", "rating_longhaul": "CHOPPY", "stable_window_domestic": "10-20", "stable_window_longhaul": "10-20", "note": "Starlink rollout mid-2026"},
    "AS": {"name": "Alaska Airlines", "rating_domestic": "CHOPPY", "rating_longhaul": "CHOPPY", "stable_window_domestic": "15-30", "stable_window_longhaul": "15-30", "note": "Starlink installs underway"},
    "AC": {"name": "Air Canada", "rating_domestic": "GOOD", "rating_longhaul": "USABLE", "stable_window_domestic": "30-60", "stable_window_longhaul": "30-60", "note": "Free for Aeroplan members"},
    "AF": {"name": "Air France", "rating_domestic": "EXCELLENT", "rating_longhaul": "EXCELLENT", "stable_window_domestic": "60+", "stable_window_longhaul": "60+", "note": "Starlink fleet; free Flying Blue"},
    "KL": {"name": "KLM", "rating_domestic": "GOOD", "rating_longhaul": "GOOD", "stable_window_domestic": "30-60", "stable_window_longhaul": "30-60", "note": "European routes; free Flying Blue"},
    "LH": {"name": "Lufthansa", "rating_domestic": "CHOPPY", "rating_longhaul": "CHOPPY", "stable_window_domestic": "10-20", "stable_window_longhaul": "10-20", "note": "Hardware lottery; limited Starlink fleet until 2029"},
    "EY": {"name": "Etihad Airways", "rating_domestic": "GOOD", "rating_longhaul": "GOOD", "stable_window_domestic": "30-45", "stable_window_longhaul": "30-45", "note": "New aircraft solid; legacy fleet USABLE"},
    "EK": {"name": "Emirates", "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "Premium tier needed for API"},
    "QR": {"name": "Qatar Airways", "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "Varies by aircraft type"},
    "CX": {"name": "Cathay Pacific", "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "600-900ms latency; 1-2 drops/flight"},
    "SQ": {"name": "Singapore Airlines", "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "Workable; premium cabin complimentary"},
    "NH": {"name": "ANA", "rating_domestic": "GOOD", "rating_longhaul": "CHOPPY", "stable_window_domestic": "30-60", "stable_window_longhaul": "10-20", "note": "767 Viasat good; 777 long-haul hour-long blackouts possible"},
    "TG": {"name": "Thai Airways", "rating_domestic": "GOOD", "rating_longhaul": "GOOD", "stable_window_domestic": "30-60", "stable_window_longhaul": "30-60", "note": "Multi-orbit pioneer; legacy fleet CHOPPY"},
    "AI": {"name": "Air India", "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "Portal login finicky"},
    "6E": {"name": "IndiGo", "rating_domestic": "POOR", "rating_longhaul": "POOR", "stable_window_domestic": "0", "stable_window_longhaul": "0", "note": "No WiFi until late 2025"},
    "FR": {"name": "Ryanair", "rating_domestic": "POOR", "rating_longhaul": "POOR", "stable_window_domestic": "0", "stable_window_longhaul": "0", "note": "No viable WiFi"},
    "U2": {"name": "easyJet", "rating_domestic": "POOR", "rating_longhaul": "POOR", "stable_window_domestic": "0", "stable_window_longhaul": "0", "note": "No viable WiFi"},
    "W6": {"name": "Wizz Air", "rating_domestic": "POOR", "rating_longhaul": "POOR", "stable_window_domestic": "0", "stable_window_longhaul": "0", "note": "No viable WiFi"},
    "HA": {"name": "Hawaiian Airlines", "rating_domestic": "EXCELLENT", "rating_longhaul": "EXCELLENT", "stable_window_domestic": "60+", "stable_window_longhaul": "60+", "note": "Starlink equipped"},
    "QF": {"name": "Qantas", "rating_domestic": "GOOD", "rating_longhaul": "USABLE", "stable_window_domestic": "30-60", "stable_window_longhaul": "20-40", "note": "Viasat Ka-band"},
    "BA": {"name": "British Airways", "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "Gogo 2Ku; variable quality"},
    "VS": {"name": "Virgin Atlantic", "rating_domestic": "GOOD", "rating_longhaul": "GOOD", "stable_window_domestic": "30-60", "stable_window_longhaul": "30-60", "note": "Viasat Ka-band"},
    "JL": {"name": "Japan Airlines", "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "Free WiFi all classes"},
    "KE": {"name": "Korean Air", "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "Panasonic Ku-band"},
    "TK": {"name": "Turkish Airlines", "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "Panasonic; free business class"},
    "LA": {"name": "LATAM Airlines", "rating_domestic": "USABLE", "rating_longhaul": "USABLE", "stable_window_domestic": "20-40", "stable_window_longhaul": "20-40", "note": "Gogo 2Ku"},
    "SK": {"name": "SAS", "rating_domestic": "GOOD", "rating_longhaul": "GOOD", "stable_window_domestic": "30-60", "stable_window_longhaul": "30-60", "note": "Viasat Ka-band"},
    "FI": {"name": "Icelandair", "rating_domestic": "GOOD", "rating_longhaul": "GOOD", "stable_window_domestic": "30-60", "stable_window_longhaul": "30-60", "note": "Viasat Ka-band"}
  },
  "default": {
    "name": "Unknown Carrier",
    "rating_domestic": "USABLE",
    "rating_longhaul": "USABLE",
    "stable_window_domestic": "20-40",
    "stable_window_longhaul": "20-40",
    "note": "Unknown carrier — using conservative defaults"
  },
  "calibration": {
    "EXCELLENT": {"batch_size": "up to 5", "checkpoint_interval": "4-5", "commit_interval": "4-5"},
    "GOOD":      {"batch_size": "up to 3", "checkpoint_interval": "3-4", "commit_interval": "3-4"},
    "USABLE":    {"batch_size": "1-2", "checkpoint_interval": "2-3", "commit_interval": "2-3"},
    "CHOPPY":    {"batch_size": "1", "checkpoint_interval": "1-2", "commit_interval": "1-2"},
    "POOR":      {"batch_size": "1, minimal reads", "checkpoint_interval": "1", "commit_interval": "1"},
    "UNKNOWN":   {"batch_size": "1-2", "checkpoint_interval": "2-3", "commit_interval": "2-3"}
  },
  "route_type_thresholds": {
    "_note": "Duration thresholds to classify domestic vs long-haul. Used to select rating_domestic or rating_longhaul.",
    "domestic_max_hours": 6
  }
}
```

**Step 2: Validate JSON**

Run: `jq . data/airline-profiles.json > /dev/null && echo "Valid JSON"`

Expected: "Valid JSON"

**Step 3: Commit**

```bash
git add data/airline-profiles.json
git commit -m "feat: add airline-profiles.json for programmatic lookup"
```

---

### Task 2: Create `scripts/flight-on-lookup.sh`

**Files:**
- Create: `scripts/flight-on-lookup.sh`

**Step 1: Write the lookup script**

This script takes airline_code + origin + destination, looks up the profile and corridor, writes route-data.json to the dashboard, and outputs the lookup result.

```bash
#!/bin/bash
# Flight Mode — Lookup: profile + corridor matching + dashboard route-data write
# Input: JSON on stdin with airline_code, origin, destination, plugin_dir, dashboard_dir
# Output: JSON with rating, corridor, duration, waypoints, weak_zone, calibration
set -uo pipefail

INPUT=$(cat)
AIRLINE_CODE=$(echo "$INPUT" | jq -r '.airline_code // empty')
ORIGIN=$(echo "$INPUT" | jq -r '.origin // empty')
DESTINATION=$(echo "$INPUT" | jq -r '.destination // empty')
PLUGIN_DIR=$(echo "$INPUT" | jq -r '.plugin_dir // empty')
DASHBOARD_DIR=$(echo "$INPUT" | jq -r '.dashboard_dir // empty')

if [ -z "$PLUGIN_DIR" ]; then
  PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
fi

PROFILES_FILE="$PLUGIN_DIR/data/airline-profiles.json"
AIRLINES_FILE="$PLUGIN_DIR/data/airline-codes.json"
CORRIDORS_FILE="$PLUGIN_DIR/data/route-corridors.json"
AIRPORTS_FILE="$PLUGIN_DIR/data/airport-codes.json"
EGRESS_FILE="$PLUGIN_DIR/data/provider-egress.json"

# Run the full lookup in Python
AIRLINE_CODE_VAR="$AIRLINE_CODE" \
ORIGIN_VAR="${ORIGIN:-}" \
DESTINATION_VAR="${DESTINATION:-}" \
PROFILES_VAR="$PROFILES_FILE" \
AIRLINES_VAR="$AIRLINES_FILE" \
CORRIDORS_VAR="$CORRIDORS_FILE" \
AIRPORTS_VAR="$AIRPORTS_FILE" \
EGRESS_VAR="$EGRESS_FILE" \
DASHBOARD_DIR_VAR="${DASHBOARD_DIR:-}" \
python3 <<'PYEOF'
import json, os, sys, math

def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}

airline_code = os.environ.get("AIRLINE_CODE_VAR", "")
origin = os.environ.get("ORIGIN_VAR", "").upper()
destination = os.environ.get("DESTINATION_VAR", "").upper()
dashboard_dir = os.environ.get("DASHBOARD_DIR_VAR", "")

profiles_data = load(os.environ["PROFILES_VAR"])
airlines_data = load(os.environ["AIRLINES_VAR"])
corridors_data = load(os.environ["CORRIDORS_VAR"])
airports_data = load(os.environ["AIRPORTS_VAR"])
egress_data = load(os.environ["EGRESS_VAR"])

# 1. Profile lookup
profiles = profiles_data.get("profiles", {})
default_profile = profiles_data.get("default", {})
calibration_table = profiles_data.get("calibration", {})
domestic_max = profiles_data.get("route_type_thresholds", {}).get("domestic_max_hours", 6)

profile = profiles.get(airline_code.upper(), default_profile)

# 2. Get provider from airline-codes.json
airline_info = airlines_data.get(airline_code.upper(), {})
provider = airline_info.get("provider", "unknown")
airline_name = profile.get("name", airline_info.get("name", "Unknown"))

# 3. Provider egress
providers = egress_data.get("providers", {})
provider_info = providers.get(provider, providers.get("unknown", {}))

# 4. Corridor matching
# Get lat/lon for origin and destination
airports_data.pop("_note", None)
origin_info = airports_data.get(origin, {})
dest_info = airports_data.get(destination, {})

def haversine(lat1, lon1, lat2, lon2):
    R = 6371
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
    return R * 2 * math.asin(math.sqrt(a))

best_corridor = None
best_score = float('inf')
corridors = corridors_data.get("corridors", {})

if origin_info and dest_info:
    olat, olon = origin_info.get("lat", 0), origin_info.get("lon", 0)
    dlat, dlon = dest_info.get("lat", 0), dest_info.get("lon", 0)
    route_dist = haversine(olat, olon, dlat, dlon)

    for cid, corridor in corridors.items():
        if cid.startswith("_"):
            continue
        examples = corridor.get("examples", [])
        # Check for exact route match first
        route_str = f"{origin}-{destination}"
        route_rev = f"{destination}-{origin}"
        if route_str in examples or route_rev in examples:
            best_corridor = (cid, corridor)
            best_score = 0
            break

        # Score by: compare route distance to corridor duration (proxy for distance)
        # and check if origin/destination countries match corridor examples
        wp = corridor.get("waypoints", [])
        if len(wp) < 2:
            continue
        # Distance from origin to corridor start + destination to corridor end
        c_start_lat, c_start_lon = wp[0].get("lat", 0), wp[0].get("lon", 0)
        c_end_lat, c_end_lon = wp[-1].get("lat", 0), wp[-1].get("lon", 0)
        score_fwd = haversine(olat, olon, c_start_lat, c_start_lon) + haversine(dlat, dlon, c_end_lat, c_end_lon)
        score_rev = haversine(olat, olon, c_end_lat, c_end_lon) + haversine(dlat, dlon, c_start_lat, c_start_lon)
        score = min(score_fwd, score_rev)

        if score < best_score:
            best_score = score
            best_corridor = (cid, corridor)

# 5. Build result
if best_corridor:
    cid, corridor = best_corridor
    duration = corridor.get("duration_hours", 5)
    waypoints = corridor.get("waypoints", [])
    weak_zone = corridor.get("weak_zone", None)
else:
    # Fallback: estimate duration from distance
    if origin_info and dest_info:
        dist = haversine(origin_info["lat"], origin_info["lon"], dest_info["lat"], dest_info["lon"])
        duration = round(dist / 850, 1)  # ~850 km/h cruise
    else:
        duration = 5
    cid = "unknown"
    waypoints = []
    weak_zone = None

# 6. Determine rating (domestic vs long-haul)
is_longhaul = duration > domestic_max
rating = profile.get("rating_longhaul" if is_longhaul else "rating_domestic", "USABLE")
stable_window = profile.get("stable_window_longhaul" if is_longhaul else "stable_window_domestic", "20-40")

# 7. Calibration
calibration = calibration_table.get(rating, calibration_table.get("UNKNOWN", {}))

# 8. Build output
result = {
    "airline_name": airline_name,
    "provider": provider,
    "provider_egress": provider_info.get("egress_countries", []),
    "provider_risk": provider_info.get("risk", "unknown"),
    "rating": rating,
    "stable_window": stable_window,
    "note": profile.get("note", ""),
    "corridor": cid,
    "corridor_name": best_corridor[1].get("name", "Unknown") if best_corridor else "Unknown",
    "duration_hours": duration,
    "waypoints": waypoints,
    "weak_zone": weak_zone,
    "calibration": calibration
}

# 9. Write route-data.json to dashboard directory
if dashboard_dir:
    route_data = {
        "flight": airline_code,
        "airline": airline_name,
        "route": f"{origin}-{destination}",
        "provider": provider,
        "rating": rating,
        "duration_hours": duration,
        "takeoff_time": None,  # Will be set by Claude or user
        "waypoints": waypoints,
        "weak_zone": weak_zone
    }
    try:
        with open(os.path.join(dashboard_dir, "route-data.json"), "w") as f:
            json.dump(route_data, f)
    except Exception:
        pass

print(json.dumps(result, indent=2))
PYEOF
```

**Step 2: Make executable**

Run: `chmod +x scripts/flight-on-lookup.sh`

**Step 3: Test with CX BLR-HKG**

Run:
```bash
echo '{"airline_code":"CX","origin":"BLR","destination":"HKG","plugin_dir":"/Users/Aakash/Claude Projects/Flight Mode","dashboard_dir":""}' | bash scripts/flight-on-lookup.sh
```

Expected: JSON with `rating: "USABLE"`, `corridor: "intra-asia"`, `duration_hours: 5`, waypoints array, calibration object.

**Step 4: Test with DL JFK-LAX (US domestic)**

Run:
```bash
echo '{"airline_code":"DL","origin":"JFK","destination":"LAX","plugin_dir":"/Users/Aakash/Claude Projects/Flight Mode","dashboard_dir":""}' | bash scripts/flight-on-lookup.sh
```

Expected: JSON with `rating: "GOOD"` (domestic), `corridor: "us-domestic"`, `duration_hours: 5`.

**Step 5: Test with unknown airline**

Run:
```bash
echo '{"airline_code":"XX","origin":"JFK","destination":"LAX","plugin_dir":"/Users/Aakash/Claude Projects/Flight Mode","dashboard_dir":""}' | bash scripts/flight-on-lookup.sh
```

Expected: JSON with default profile (`rating: "USABLE"`), corridor still matches.

**Step 6: Commit**

```bash
git add scripts/flight-on-lookup.sh
git commit -m "feat: add flight-on-lookup.sh for profile + corridor matching"
```

---

### Task 3: Create `scripts/flight-on-preflight.sh`

**Files:**
- Create: `scripts/flight-on-preflight.sh`

**Step 1: Write the preflight orchestrator**

This script calls parse-flight, network-detect, flight-check, starts the dashboard, and optionally runs lookup. It outputs a single JSON blob.

```bash
#!/bin/bash
# Flight Mode — Preflight Orchestrator
# Runs ALL environment checks deterministically. Called via !`command` in SKILL.md.
# Input: $1 = user arguments (may be empty), $2 = plugin directory
# Output: Single JSON blob with parse, network, api, dashboard, lookup results
set -uo pipefail

FLIGHT_ARGS="${1:-}"
PLUGIN_DIR="${2:-${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}}"

SCRIPTS_DIR="$PLUGIN_DIR/scripts"

# --- 1. Parse flight input ---
PARSE_RESULT=$(echo "{\"input\": \"$FLIGHT_ARGS\", \"plugin_dir\": \"$PLUGIN_DIR\"}" | bash "$SCRIPTS_DIR/parse-flight.sh" 2>/dev/null) || PARSE_RESULT='{"confidence":"none"}'

# --- 2. Network detection ---
NETWORK_RESULT=$(echo "{\"plugin_dir\": \"$PLUGIN_DIR\"}" | bash "$SCRIPTS_DIR/network-detect.sh" 2>/dev/null) || NETWORK_RESULT='{"type":"unknown","ssid":null}'

# --- 3. API availability check ---
API_RESULT=$(echo "{\"plugin_dir\": \"$PLUGIN_DIR\"}" | bash "$SCRIPTS_DIR/flight-check.sh" 2>/dev/null) || API_RESULT='{"verdict":"OFFLINE"}'

# --- 4. Start dashboard ---
DASHBOARD_RESULT=$(echo "{\"command\":\"start\",\"plugin_dir\":\"$PLUGIN_DIR\"}" | bash "$SCRIPTS_DIR/dashboard-server.sh" 2>/dev/null) || DASHBOARD_RESULT='{"status":"error"}'

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
  LOOKUP_RESULT=$(echo "{\"airline_code\":\"$AIRLINE_CODE\",\"origin\":\"$ORIGIN\",\"destination\":\"$DESTINATION\",\"plugin_dir\":\"$PLUGIN_DIR\",\"dashboard_dir\":\"$DASHBOARD_DIR\"}" | bash "$SCRIPTS_DIR/flight-on-lookup.sh" 2>/dev/null) || LOOKUP_RESULT="null"
fi

# --- 7. Assemble final output ---
# Use Python to merge all JSON results into one clean object
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
```

**Step 2: Make executable**

Run: `chmod +x scripts/flight-on-preflight.sh`

**Step 3: Test with full args (CX HKG-LAX)**

Run:
```bash
bash scripts/flight-on-preflight.sh "CX HKG-LAX" "/Users/Aakash/Claude Projects/Flight Mode"
```

Expected: JSON with all 5 sections populated, `ready: true`, `missing: []`, `lookup` has corridor/rating data, dashboard started.

**Step 4: Test with partial args (CX624)**

Run:
```bash
bash scripts/flight-on-preflight.sh "CX624" "/Users/Aakash/Claude Projects/Flight Mode"
```

Expected: `ready: false`, `missing: ["route"]`, `lookup: null`, parse has airline_code "CX".

**Step 5: Test with no args**

Run:
```bash
bash scripts/flight-on-preflight.sh "" "/Users/Aakash/Claude Projects/Flight Mode"
```

Expected: `ready: false`, `missing: ["airline","route"]`, `lookup: null`.

**Step 6: Stop dashboard (cleanup)**

Run:
```bash
echo '{"command":"stop","plugin_dir":"/Users/Aakash/Claude Projects/Flight Mode"}' | bash scripts/dashboard-server.sh
```

**Step 7: Commit**

```bash
git add scripts/flight-on-preflight.sh
git commit -m "feat: add flight-on-preflight.sh orchestrator"
```

---

### Task 4: Create `scripts/flight-on-activate.sh`

**Files:**
- Create: `scripts/flight-on-activate.sh`

**Step 1: Write the activation script**

Takes all gathered data as JSON on stdin, writes FLIGHT_MODE.md and .flight-state.md.

```bash
#!/bin/bash
# Flight Mode — Activation: writes FLIGHT_MODE.md + .flight-state.md
# Input: JSON on stdin with all flight data + cwd
# Output: JSON confirmation
set -uo pipefail

INPUT=$(cat)

# Extract fields
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ]; then
  CWD="$(pwd)"
fi

AIRLINE_CODE=$(echo "$INPUT" | jq -r '.airline_code // "??"')
AIRLINE_NAME=$(echo "$INPUT" | jq -r '.airline_name // "Unknown"')
ORIGIN=$(echo "$INPUT" | jq -r '.origin // "???"')
DESTINATION=$(echo "$INPUT" | jq -r '.destination // "???"')
PROVIDER=$(echo "$INPUT" | jq -r '.provider // "unknown"')
RATING=$(echo "$INPUT" | jq -r '.rating // "USABLE"')
STABLE_WINDOW=$(echo "$INPUT" | jq -r '.stable_window // "20-40"')
DURATION=$(echo "$INPUT" | jq -r '.duration_hours // 5')
API_VERDICT=$(echo "$INPUT" | jq -r '.api_verdict // "UNKNOWN"')
EGRESS_COUNTRY=$(echo "$INPUT" | jq -r '.egress_country // "??"')
DASHBOARD_URL=$(echo "$INPUT" | jq -r '.dashboard_url // "http://localhost:8234"')
BATCH_SIZE=$(echo "$INPUT" | jq -r '.calibration.batch_size // "1-2"')
CHECKPOINT=$(echo "$INPUT" | jq -r '.calibration.checkpoint_interval // "2-3"')
COMMIT_INT=$(echo "$INPUT" | jq -r '.calibration.commit_interval // "2-3"')

# Weak zone (may be null)
WZ_START=$(echo "$INPUT" | jq -r '.weak_zone.start_hour // empty')
WZ_END=$(echo "$INPUT" | jq -r '.weak_zone.end_hour // empty')
WZ_REASON=$(echo "$INPUT" | jq -r '.weak_zone.reason // empty')

DATE_NOW=$(date +"%Y-%m-%d %H:%M")
PROJECT_NAME=$(basename "$CWD")

# --- Write FLIGHT_MODE.md ---
WEAK_ZONE_LINE=""
if [ -n "$WZ_START" ] && [ -n "$WZ_END" ]; then
  WEAK_ZONE_LINE="**Weak Zone:** Hours ${WZ_START}-${WZ_END} — ${WZ_REASON}"
fi

cat > "$CWD/FLIGHT_MODE.md" << FMEOF
# Flight Mode Active

**Airline:** ${AIRLINE_NAME} ${AIRLINE_CODE}
**Route:** ${ORIGIN} -> ${DESTINATION} (~${DURATION}h)
**WiFi:** ${PROVIDER} · Rating: ${RATING}
**API Status:** ${API_VERDICT} via ${EGRESS_COUNTRY}
**Activated:** ${DATE_NOW}
**Stable Window:** ${STABLE_WINDOW} min
**Dashboard:** ${DASHBOARD_URL}
${WEAK_ZONE_LINE:+
$WEAK_ZONE_LINE}

## Condensed Protocol (for session recovery)

1. **Read \`.flight-state.md\`** — resume from last incomplete micro-task
2. **Micro-tasks only** — max ${BATCH_SIZE} tool calls per task, decompose before starting
3. **Checkpoint every ${CHECKPOINT} tasks** — update \`.flight-state.md\` + git commit
4. **Git discipline** — \`flight:\` prefix, stage specific files (not \`git add -A\`), skip failed pre-commit hooks
5. **Context budget** — minimize file reads, read only what the current micro-task needs
6. **If a drop seems imminent** — finish current edit, commit immediately, update \`.flight-state.md\`
7. **Every edit must be self-contained** — never leave files in an inconsistent state
FMEOF

# --- Write .flight-state.md ---
cat > "$CWD/.flight-state.md" << FSEOF
# Flight State

**Session started:** ${DATE_NOW}
**Airline:** ${AIRLINE_NAME} ${AIRLINE_CODE} ${ORIGIN}-${DESTINATION}
**WiFi:** ${PROVIDER} · Rating: ${RATING}
**API Status:** ${API_VERDICT}
**Project:** ${PROJECT_NAME}

## Current Task
(awaiting user input)

## Micro-Tasks
(not yet decomposed)

## Last Action
Flight mode activated. Awaiting task assignment.

## Files Modified This Session
(none yet)

## Recovery Instructions
If this session dropped: Flight mode is active but no task was assigned yet. Ask the user what they want to work on.
FSEOF

# --- Output confirmation ---
cat << OUTEOF
{
  "status": "activated",
  "flight_mode_path": "$CWD/FLIGHT_MODE.md",
  "flight_state_path": "$CWD/.flight-state.md"
}
OUTEOF
```

**Step 2: Make executable**

Run: `chmod +x scripts/flight-on-activate.sh`

**Step 3: Test (write to /tmp to avoid polluting repo)**

Run:
```bash
echo '{"airline_code":"CX","airline_name":"Cathay Pacific","origin":"BLR","destination":"HKG","provider":"gogo","rating":"USABLE","stable_window":"20-40","duration_hours":5.5,"api_verdict":"GO","egress_country":"US","dashboard_url":"http://localhost:8234","weak_zone":null,"calibration":{"batch_size":"1-2","checkpoint_interval":"2-3","commit_interval":"2-3"},"cwd":"/tmp/flight-test"}' | bash scripts/flight-on-activate.sh
```

Then verify:
```bash
mkdir -p /tmp/flight-test && cat /tmp/flight-test/FLIGHT_MODE.md && echo "---" && cat /tmp/flight-test/.flight-state.md && rm -rf /tmp/flight-test
```

Expected: Both files contain correct data. FLIGHT_MODE.md has condensed protocol. .flight-state.md has initial state.

**Step 4: Test with weak zone**

Run:
```bash
echo '{"airline_code":"CX","airline_name":"Cathay Pacific","origin":"HKG","destination":"LAX","provider":"gogo","rating":"USABLE","stable_window":"20-40","duration_hours":13,"api_verdict":"GO","egress_country":"US","dashboard_url":"http://localhost:8234","weak_zone":{"start_hour":5,"end_hour":8,"reason":"Central Pacific"},"calibration":{"batch_size":"1-2","checkpoint_interval":"2-3","commit_interval":"2-3"},"cwd":"/tmp/flight-test"}' | bash scripts/flight-on-activate.sh
```

Expected: FLIGHT_MODE.md includes "**Weak Zone:** Hours 5-8 — Central Pacific"

Cleanup: `rm -rf /tmp/flight-test`

**Step 5: Commit**

```bash
git add scripts/flight-on-activate.sh
git commit -m "feat: add flight-on-activate.sh for FLIGHT_MODE.md creation"
```

---

### Task 5: Create `scripts/block-direct-flight-mode.sh` and update `hooks/hooks.json`

**Files:**
- Create: `scripts/block-direct-flight-mode.sh`
- Modify: `hooks/hooks.json`

**Step 1: Write the safety hook script**

```bash
#!/bin/bash
# Blocks direct Write to FLIGHT_MODE.md — forces use of flight-on-activate.sh
# PreToolUse hook for Write tool
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if echo "$FILE_PATH" | grep -qF "FLIGHT_MODE.md"; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "FLIGHT_MODE.md must be created by flight-on-activate.sh, not written directly. Use the activate script."
  }
}
EOF
  exit 0
fi

exit 0
```

**Step 2: Make executable**

Run: `chmod +x scripts/block-direct-flight-mode.sh`

**Step 3: Update hooks/hooks.json**

Add a new PreToolUse entry for Write. The existing hooks.json has Stop and PostToolUse. Add PreToolUse:

Current `hooks/hooks.json`:
```json
{
  "description": "...",
  "hooks": {
    "Stop": [...],
    "PostToolUse": [...]
  }
}
```

Add `PreToolUse` key:
```json
"PreToolUse": [
  {
    "matcher": "Write",
    "hooks": [
      {
        "type": "command",
        "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/block-direct-flight-mode.sh\"",
        "timeout": 5
      }
    ]
  }
]
```

**Step 4: Validate hooks.json**

Run: `jq . hooks/hooks.json > /dev/null && echo "Valid"`

Expected: "Valid"

**Step 5: Test the hook script**

Run:
```bash
echo '{"tool_name":"Write","tool_input":{"file_path":"/some/path/FLIGHT_MODE.md","content":"test"}}' | bash scripts/block-direct-flight-mode.sh
```

Expected: JSON with `permissionDecision: "deny"`

Run:
```bash
echo '{"tool_name":"Write","tool_input":{"file_path":"/some/path/other.md","content":"test"}}' | bash scripts/block-direct-flight-mode.sh
```

Expected: Empty output (exit 0, no block)

**Step 6: Commit**

```bash
git add scripts/block-direct-flight-mode.sh hooks/hooks.json
git commit -m "feat: add safety hook to block direct FLIGHT_MODE.md writes"
```

---

### Task 6: Rewrite `skills/flight-on/SKILL.md`

**Files:**
- Modify: `skills/flight-on/SKILL.md` (full rewrite)

**Step 1: Write the new SKILL.md**

Replace the entire file. The new version uses `!`command`` for preflight and has a thin instruction layer for Claude. Keep the behavioral protocol (Rules 1-7) unchanged from the current file.

Key structure:
1. Frontmatter (same as before, minus Agent from allowed-tools)
2. `!`command`` block that runs preflight
3. Step 1: Check `ready` field
4. Step 2: Ask user for missing info + run lookup script
5. Step 3: Present summary
6. HARD GATE: "Activate? (y/n)"
7. Step 4: Run activate script
8. Step 5: Check .gitignore
9. Behavioral Protocol (Rules 1-7 — copy unchanged from current file)
10. Post-Flight Squash Reference (copy unchanged)

The `!`command`` line:
```markdown
!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/flight-on-preflight.sh" "$ARGUMENTS" "${CLAUDE_PLUGIN_ROOT}" 2>/dev/null || echo '{"error":"preflight script failed","ready":false,"missing":["airline","route"]}'`
```

**Step 2: Verify skill loads**

The skill can be tested by inspecting the SKILL.md format — frontmatter is valid YAML, `!`command`` syntax is correct, all `${CLAUDE_PLUGIN_ROOT}` references use the right syntax.

Run: `head -10 skills/flight-on/SKILL.md` — verify frontmatter.

**Step 3: Commit**

```bash
git add skills/flight-on/SKILL.md
git commit -m "feat: rewrite flight-on skill with deterministic command injection"
```

---

### Task 7: Integration test — full preflight flow

**Files:**
- No new files

**Step 1: Test preflight with full args**

Run:
```bash
bash scripts/flight-on-preflight.sh "CX HKG-LAX" "/Users/Aakash/Claude Projects/Flight Mode"
```

Verify output has all 5 sections populated, `ready: true`.

**Step 2: Verify dashboard is running**

Run:
```bash
curl -s -o /dev/null -w '%{http_code}' http://localhost:8234/
```

Expected: `200`

**Step 3: Verify route-data.json was written**

Run:
```bash
ls /tmp/flight-mode-dashboard-*/route-data.json && cat /tmp/flight-mode-dashboard-*/route-data.json | jq .
```

Expected: JSON with flight, airline, route, provider, rating, waypoints.

**Step 4: Test lookup separately (for partial args scenario)**

Run:
```bash
DASH_DIR=$(ls -d /tmp/flight-mode-dashboard-* 2>/dev/null | head -1)
echo "{\"airline_code\":\"DL\",\"origin\":\"JFK\",\"destination\":\"LAX\",\"plugin_dir\":\"/Users/Aakash/Claude Projects/Flight Mode\",\"dashboard_dir\":\"$DASH_DIR\"}" | bash scripts/flight-on-lookup.sh
```

Expected: Delta lookup, US domestic corridor, rating GOOD.

**Step 5: Test activate (to /tmp)**

Run:
```bash
mkdir -p /tmp/flight-test
echo '{"airline_code":"CX","airline_name":"Cathay Pacific","origin":"HKG","destination":"LAX","provider":"gogo","rating":"USABLE","stable_window":"20-40","duration_hours":13,"api_verdict":"GO","egress_country":"US","dashboard_url":"http://localhost:8234","weak_zone":{"start_hour":5,"end_hour":8,"reason":"Central Pacific"},"calibration":{"batch_size":"1-2","checkpoint_interval":"2-3","commit_interval":"2-3"},"cwd":"/tmp/flight-test"}' | bash scripts/flight-on-activate.sh
cat /tmp/flight-test/FLIGHT_MODE.md
rm -rf /tmp/flight-test
```

Expected: FLIGHT_MODE.md with all fields populated including weak zone.

**Step 6: Cleanup**

```bash
echo '{"command":"stop","plugin_dir":"/Users/Aakash/Claude Projects/Flight Mode"}' | bash scripts/dashboard-server.sh
```

**Step 7: Commit (integration test results — no code changes)**

No commit needed — this is a verification step.

---

### Task 8: Run existing test suite

**Files:**
- No changes

**Step 1: Run all existing V2 tests**

Run:
```bash
for t in tests/test-v2-*.sh; do echo "=== $t ==="; bash "$t" 2>&1 | tail -3; done
```

Expected: All 173 tests still pass. The new scripts don't modify any existing code.

**Step 2: If any test fails, investigate and fix**

The new code should not affect existing tests since we only added new files and modified hooks.json (added a new entry, didn't change existing ones).

---

### Task 9: Reinstall plugin and verify

**Files:**
- No changes

**Step 1: Reinstall the plugin**

Run:
```bash
claude plugin install "/Users/Aakash/Claude Projects/Flight Mode" --scope user
```

This picks up the new hooks.json and SKILL.md.

**Step 2: Verify hooks loaded**

In a new Claude session, run `/hooks` and verify the new PreToolUse Write hook appears.

**Step 3: Push to GitHub**

```bash
cd "/Users/Aakash/Claude Projects/Flight Mode"
git push origin main
```
