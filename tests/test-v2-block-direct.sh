#!/bin/bash
# Flight Mode — V2 Test Suite: block-direct-flight-mode.sh
# Tests the PreToolUse hook that prevents direct writes to FLIGHT_MODE.md
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$PLUGIN_DIR/scripts/block-direct-flight-mode.sh"
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
# Prerequisites
# ═══════════════════════════════════════════════════
section "BD.0: Prerequisites"

if [ ! -f "$SCRIPT" ]; then
  fail "BD.0a block-direct-flight-mode.sh exists" "file missing at $SCRIPT"
  log ""
  log "Cannot continue without block-direct-flight-mode.sh"
  exit 1
fi

if [ ! -x "$SCRIPT" ]; then
  fail "BD.0b block-direct-flight-mode.sh is executable" "not executable"
else
  pass "BD.0b block-direct-flight-mode.sh is executable"
fi

if ! command -v jq >/dev/null 2>&1; then
  fail "BD.0c jq is installed" "jq not found — cannot run tests"
  exit 1
fi
pass "BD.0c jq is installed"

# ═══════════════════════════════════════════════════
# BD.1: Blocks write to FLIGHT_MODE.md
# ═══════════════════════════════════════════════════
section "BD.1: Block Write to FLIGHT_MODE.md"

OUTPUT=$(echo '{"tool_input":{"file_path":"/some/path/FLIGHT_MODE.md"}}' | bash "$SCRIPT" 2>/dev/null)
RC=$?

if [ $RC -eq 0 ]; then
  pass "BD.1a exit code 0"
else
  fail "BD.1a exit code" "expected 0, got $RC"
fi

if echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1; then
  DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
  if [ "$DECISION" = "deny" ]; then
    pass "BD.1b output contains deny decision"
  else
    fail "BD.1b deny decision" "got: $DECISION"
  fi
else
  fail "BD.1b deny output" "no hookSpecificOutput.permissionDecision in output: $OUTPUT"
fi

# ═══════════════════════════════════════════════════
# BD.2: Allows write to other files
# ═══════════════════════════════════════════════════
section "BD.2: Allow Write to Other Files"

OUTPUT=$(echo '{"tool_input":{"file_path":"/some/path/other.txt"}}' | bash "$SCRIPT" 2>/dev/null)
RC=$?

if [ $RC -eq 0 ]; then
  pass "BD.2a exit code 0"
else
  fail "BD.2a exit code" "expected 0, got $RC"
fi

if [ -z "$OUTPUT" ]; then
  pass "BD.2b empty output (passes through)"
else
  # Check it doesn't contain deny
  DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$DECISION" = "deny" ]; then
    fail "BD.2b passthrough" "incorrectly denied write to other.txt"
  else
    pass "BD.2b output does not deny (output present but no deny)"
  fi
fi

# ═══════════════════════════════════════════════════
# BD.3: Handles missing file_path
# ═══════════════════════════════════════════════════
section "BD.3: Missing file_path"

OUTPUT=$(echo '{"tool_input":{}}' | bash "$SCRIPT" 2>/dev/null)
RC=$?

if [ $RC -eq 0 ]; then
  pass "BD.3a exit code 0"
else
  fail "BD.3a exit code" "expected 0, got $RC"
fi

if [ -z "$OUTPUT" ]; then
  pass "BD.3b empty output (passes through)"
else
  DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$DECISION" = "deny" ]; then
    fail "BD.3b passthrough" "incorrectly denied with no file_path"
  else
    pass "BD.3b output does not deny"
  fi
fi

# ═══════════════════════════════════════════════════
# BD.4: Handles empty input
# ═══════════════════════════════════════════════════
section "BD.4: Empty Input"

OUTPUT=$(echo '{}' | bash "$SCRIPT" 2>/dev/null)
RC=$?

if [ $RC -eq 0 ]; then
  pass "BD.4a exit code 0"
else
  fail "BD.4a exit code" "expected 0, got $RC"
fi

if [ -z "$OUTPUT" ]; then
  pass "BD.4b empty output (passes through)"
else
  DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$DECISION" = "deny" ]; then
    fail "BD.4b passthrough" "incorrectly denied with empty input"
  else
    pass "BD.4b output does not deny"
  fi
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
  log "${GREEN}All block-direct tests passed!${NC}"
else
  log "${RED}$FAIL test(s) failed — see details above${NC}"
fi

exit $FAIL
