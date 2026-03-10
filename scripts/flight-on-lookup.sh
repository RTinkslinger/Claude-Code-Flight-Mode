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

# Handle variant airlines (e.g., UA_starlink vs UA_legacy)
# Pick the most conservative (worst-rated) variant as default
RATING_RANK = {"POOR": 0, "CHOPPY": 1, "USABLE": 2, "GOOD": 3, "EXCELLENT": 4}
variant_airlines = profiles_data.get("variant_airlines", {})
code_upper = airline_code.upper()
if code_upper in variant_airlines:
    variant_keys = variant_airlines[code_upper]
    best_key = variant_keys[0]
    best_rank = 99
    for vk in variant_keys:
        vp = profiles.get(vk, {})
        r = vp.get("rating_domestic") or vp.get("rating_longhaul") or "USABLE"
        rank = RATING_RANK.get(r, 2)
        if rank < best_rank:
            best_rank = rank
            best_key = vk
    profile = profiles.get(best_key, default_profile)
elif code_upper in profiles:
    profile = profiles[code_upper]
else:
    profile = default_profile

# 2. Get provider from airline-codes.json
airline_info = airlines_data.get(airline_code.upper(), {})
provider = airline_info.get("provider", "unknown")
airline_name = profile.get("name", airline_info.get("name", "Unknown"))

# 3. Provider egress
providers = egress_data.get("providers", {})
provider_info = providers.get(provider, providers.get("unknown", {}))

# 4. Corridor matching
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
        route_str = f"{origin}-{destination}"
        route_rev = f"{destination}-{origin}"
        if route_str in examples or route_rev in examples:
            best_corridor = (cid, corridor)
            best_score = 0
            break

        wp = corridor.get("waypoints", [])
        if len(wp) < 2:
            continue
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
    if origin_info and dest_info:
        dist = haversine(origin_info["lat"], origin_info["lon"], dest_info["lat"], dest_info["lon"])
        duration = round(dist / 850, 1)
    else:
        duration = 5
    cid = "unknown"
    waypoints = []
    weak_zone = None

# 6. Determine rating (handle null values from variant profiles)
is_longhaul = duration > domestic_max
if is_longhaul:
    rating = profile.get("rating_longhaul") or profile.get("rating_domestic") or "USABLE"
    stable_window = profile.get("stable_window_longhaul") or profile.get("stable_window_domestic") or "20-40"
else:
    rating = profile.get("rating_domestic") or profile.get("rating_longhaul") or "USABLE"
    stable_window = profile.get("stable_window_domestic") or profile.get("stable_window_longhaul") or "20-40"

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

# 9. Write route-data.json
if dashboard_dir:
    route_data = {
        "flight": airline_code,
        "airline": airline_name,
        "route": f"{origin}-{destination}",
        "provider": provider,
        "rating": rating,
        "duration_hours": duration,
        "takeoff_time": None,
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
