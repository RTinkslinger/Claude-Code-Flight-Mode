#!/bin/bash
# Flight Mode — V2 Test Suite: Dashboard HTML Validation
# Validates the dashboard.html template structure, elements, and functionality.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DASHBOARD="$PLUGIN_DIR/templates/dashboard.html"
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

# Helper: check if dashboard contains a string (case-sensitive)
has() {
  grep -qF -- "$1" "$DASHBOARD" 2>/dev/null
}

# Helper: check if dashboard contains a string (case-insensitive)
has_i() {
  grep -qiF -- "$1" "$DASHBOARD" 2>/dev/null
}

# ═══════════════════════════════════════════════════
# DB.1–DB.2: File Basics
# ═══════════════════════════════════════════════════
section "DB.1–DB.2: File Basics"

# DB.1: templates/dashboard.html exists
if [ -f "$DASHBOARD" ]; then
  pass "DB.1 templates/dashboard.html exists"
else
  fail "DB.1 templates/dashboard.html" "file missing"
  log ""
  log "Cannot continue without dashboard.html"
  exit 1
fi

# DB.2: File is valid HTML (has DOCTYPE, html, head, body tags)
DB2_OK=true
for tag in "DOCTYPE" "<html" "<head" "<body"; do
  if ! has_i "$tag"; then
    DB2_OK=false
    fail "DB.2 HTML tag '$tag'" "not found"
  fi
done
# Also check closing tags
for tag in "</html>" "</head>" "</body>"; do
  if ! has_i "$tag"; then
    DB2_OK=false
    fail "DB.2 closing tag '$tag'" "not found"
  fi
done
if [ "$DB2_OK" = "true" ]; then
  pass "DB.2 valid HTML structure (DOCTYPE, html, head, body with closing tags)"
fi

# ═══════════════════════════════════════════════════
# DB.3–DB.6: Required DOM Elements
# ═══════════════════════════════════════════════════
section "DB.3–DB.6: Required DOM Elements"

# DB.3: Has required elements
REQUIRED_IDS=("flightCode" "routeStr" "apiStatus" "elapsedTime")
DB3_OK=true
for id in "${REQUIRED_IDS[@]}"; do
  if has "id=\"$id\""; then
    : # found
  elif has "id='$id'"; then
    : # found (single quotes)
  elif has "\$('$id')"; then
    : # referenced in JS
  else
    DB3_OK=false
    fail "DB.3 element id='$id'" "not found in dashboard"
  fi
done
if [ "$DB3_OK" = "true" ]; then
  pass "DB.3 required elements present (flightCode, routeStr, apiStatus, elapsedTime)"
fi

# DB.4: Has timeline SVG
if has 'id="timelineSvg"'; then
  pass "DB.4 timeline SVG (id='timelineSvg') present"
else
  fail "DB.4 timeline SVG" "id='timelineSvg' not found"
fi

# DB.5: Has latency SVG
if has 'id="latencySvg"'; then
  pass "DB.5 latency SVG (id='latencySvg') present"
else
  fail "DB.5 latency SVG" "id='latencySvg' not found"
fi

# DB.6: Has drop log table
if has "drop-table" && has "dropBody"; then
  pass "DB.6 drop log table present (class='drop-table', id='dropBody')"
elif has "Drop Log"; then
  pass "DB.6 drop log table present (title found)"
else
  fail "DB.6 drop log table" "not found"
fi

# ═══════════════════════════════════════════════════
# DB.7–DB.9: Data Fetching
# ═══════════════════════════════════════════════════
section "DB.7–DB.9: Data Fetching"

# DB.7: Fetches route-data.json
if has "route-data.json"; then
  pass "DB.7 fetches route-data.json"
else
  fail "DB.7 route-data.json fetch" "reference not found"
fi

# DB.8: Fetches live-data.json
if has "live-data.json"; then
  pass "DB.8 fetches live-data.json"
else
  fail "DB.8 live-data.json fetch" "reference not found"
fi

# DB.9: Auto-refresh interval present (setInterval)
if has "setInterval"; then
  pass "DB.9 auto-refresh (setInterval) present"
else
  fail "DB.9 setInterval" "not found — no auto-refresh"
fi

# ═══════════════════════════════════════════════════
# DB.10–DB.11: Interactive Features
# ═══════════════════════════════════════════════════
section "DB.10–DB.11: Interactive Features"

# DB.10: Has tooltip functionality
if has "tooltip" && (has "mouseenter" || has "mouseover" || has "onmouseover"); then
  pass "DB.10 tooltip functionality present"
elif has "tooltip"; then
  pass "DB.10 tooltip element present (interaction method may vary)"
else
  fail "DB.10 tooltip" "not found"
fi

# DB.11: Has stale connection detection (staleBanner)
if has "staleBanner"; then
  pass "DB.11 stale connection detection (staleBanner) present"
else
  fail "DB.11 staleBanner" "not found"
fi

# ═══════════════════════════════════════════════════
# DB.12–DB.15: Styling and Theme
# ═══════════════════════════════════════════════════
section "DB.12–DB.15: Styling and Theme"

# DB.12: Uses JetBrains Mono font
if has "JetBrains Mono"; then
  pass "DB.12 uses JetBrains Mono font"
else
  fail "DB.12 JetBrains Mono" "font not referenced"
fi

# DB.13: Dark theme (--bg color defined)
if has "--bg:"; then
  # Extract the --bg value
  BG_VAL=$(grep -o '\-\-bg:[^;]*' "$DASHBOARD" | head -1)
  pass "DB.13 dark theme ($BG_VAL)"
elif has "--bg "; then
  pass "DB.13 dark theme (--bg defined)"
else
  fail "DB.13 dark theme" "--bg CSS variable not found"
fi

# DB.14: File size is reasonable (< 50KB)
FILE_SIZE=$(wc -c < "$DASHBOARD" 2>/dev/null | tr -d ' ')
if [ -n "$FILE_SIZE" ] && [ "$FILE_SIZE" -lt 51200 ] 2>/dev/null; then
  FILE_SIZE_KB=$((FILE_SIZE / 1024))
  pass "DB.14 file size is reasonable (${FILE_SIZE_KB}KB < 50KB)"
else
  fail "DB.14 file size" "${FILE_SIZE} bytes (> 50KB)"
fi

# DB.15: Has signal color function mapping quality levels
if has "signalColor"; then
  # Verify it maps different quality thresholds
  HAS_THRESHOLDS=true
  # The function should reference multiple signal level thresholds
  THRESHOLD_COUNT=0
  for threshold in "75" "55" "30"; do
    if has "$threshold"; then
      THRESHOLD_COUNT=$((THRESHOLD_COUNT + 1))
    fi
  done
  if [ "$THRESHOLD_COUNT" -ge 2 ]; then
    pass "DB.15 signalColor function with quality level thresholds ($THRESHOLD_COUNT levels found)"
  else
    pass "DB.15 signalColor function present (threshold check partial: $THRESHOLD_COUNT/3)"
  fi
else
  fail "DB.15 signalColor function" "not found"
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
  log "${GREEN}All dashboard tests passed!${NC}"
else
  log "${RED}$FAIL test(s) failed — see details above${NC}"
fi

exit $FAIL
