#!/bin/bash
# Flight Mode Plugin — Automated Test Suite
# Tests: hook scripts, plugin structure, profile data, edge cases
# Categories map to docs/test-plan.md (T5, T6, T7, T8 + structural)
# Don't use set -e — test scripts need to handle failures individually
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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
# STRUCTURAL TESTS (plugin integrity)
# ═══════════════════════════════════════════════════
section "S: Plugin Structure"

# S.1: plugin.json exists and is valid JSON
if [ -f "$PLUGIN_DIR/.claude-plugin/plugin.json" ]; then
  if jq . "$PLUGIN_DIR/.claude-plugin/plugin.json" > /dev/null 2>&1; then
    pass "S.1 plugin.json valid JSON"
  else
    fail "S.1 plugin.json valid JSON" "invalid JSON"
  fi
else
  fail "S.1 plugin.json exists" "file missing"
fi

# S.2: plugin.json has required fields
NAME=$(jq -r '.name' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null)
if [ "$NAME" = "flight-mode" ]; then
  pass "S.2 plugin.json name = flight-mode"
else
  fail "S.2 plugin.json name" "got: $NAME"
fi

# S.3: hooks.json exists and is valid JSON
if [ -f "$PLUGIN_DIR/hooks/hooks.json" ]; then
  if jq . "$PLUGIN_DIR/hooks/hooks.json" > /dev/null 2>&1; then
    pass "S.3 hooks.json valid JSON"
  else
    fail "S.3 hooks.json valid JSON" "invalid JSON"
  fi
else
  fail "S.3 hooks.json exists" "file missing"
fi

# S.4: hooks.json has Stop and PostToolUse events
STOP_HOOK=$(jq '.hooks.Stop' "$PLUGIN_DIR/hooks/hooks.json" 2>/dev/null)
POST_HOOK=$(jq '.hooks.PostToolUse' "$PLUGIN_DIR/hooks/hooks.json" 2>/dev/null)
if [ "$STOP_HOOK" != "null" ] && [ -n "$STOP_HOOK" ]; then
  pass "S.4a hooks.json has Stop event"
else
  fail "S.4a hooks.json Stop event" "missing"
fi
if [ "$POST_HOOK" != "null" ] && [ -n "$POST_HOOK" ]; then
  pass "S.4b hooks.json has PostToolUse event"
else
  fail "S.4b hooks.json PostToolUse event" "missing"
fi

# S.5: Hook scripts exist and are executable
for SCRIPT in stop-checkpoint.sh context-monitor.sh; do
  if [ -x "$PLUGIN_DIR/scripts/$SCRIPT" ]; then
    pass "S.5 scripts/$SCRIPT executable"
  elif [ -f "$PLUGIN_DIR/scripts/$SCRIPT" ]; then
    fail "S.5 scripts/$SCRIPT executable" "exists but not executable"
  else
    fail "S.5 scripts/$SCRIPT exists" "file missing"
  fi
done

# S.6: Skill files exist with YAML frontmatter
for SKILL in flight-on flight-off; do
  SKILL_FILE="$PLUGIN_DIR/skills/$SKILL/SKILL.md"
  if [ -f "$SKILL_FILE" ]; then
    if head -1 "$SKILL_FILE" | grep -q "^---"; then
      pass "S.6 skills/$SKILL/SKILL.md has frontmatter"
    else
      fail "S.6 skills/$SKILL/SKILL.md frontmatter" "missing --- header"
    fi
  else
    fail "S.6 skills/$SKILL/SKILL.md exists" "file missing"
  fi
done

# S.7: Skill frontmatter has required fields
for SKILL in flight-on flight-off; do
  SKILL_FILE="$PLUGIN_DIR/skills/$SKILL/SKILL.md"
  for FIELD in name description user-invocable; do
    if grep -q "^${FIELD}:" "$SKILL_FILE" 2>/dev/null; then
      pass "S.7 $SKILL has '$FIELD' field"
    else
      fail "S.7 $SKILL '$FIELD' field" "missing from frontmatter"
    fi
  done
done

# S.8: Data files exist
if [ -f "$PLUGIN_DIR/data/flight-profiles.md" ]; then
  pass "S.8a data/flight-profiles.md exists"
else
  fail "S.8a data/flight-profiles.md" "missing"
fi
if [ -f "$PLUGIN_DIR/templates/claude-md-snippet.md" ]; then
  pass "S.8b templates/claude-md-snippet.md exists"
else
  fail "S.8b templates/claude-md-snippet.md" "missing"
fi

# S.9: Directory structure complete
for DIR in .claude-plugin skills/flight-on skills/flight-off hooks scripts data templates; do
  if [ -d "$PLUGIN_DIR/$DIR" ]; then
    pass "S.9 directory $DIR exists"
  else
    fail "S.9 directory $DIR" "missing"
  fi
done

# ═══════════════════════════════════════════════════
# T5: Stop Hook (stop-checkpoint.sh)
# ═══════════════════════════════════════════════════
section "T5: Stop Hook (stop-checkpoint.sh)"

# Create a temp test directory with git
TEST_DIR=$(mktemp -d)
cleanup_t5() { rm -rf "$TEST_DIR"; }
trap cleanup_t5 EXIT

cd "$TEST_DIR"
git init -q
git commit --allow-empty -m "initial" -q

# T5.1: Session ends with uncommitted changes + FLIGHT_MODE.md exists
echo "# Flight Mode Active" > FLIGHT_MODE.md
echo "test content" > test.txt
git add test.txt
git commit -m "add test" -q
echo "modified" >> test.txt

OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false}' | bash "$PLUGIN_DIR/scripts/stop-checkpoint.sh" 2>&1)
RC=$?

if [ $RC -eq 0 ]; then
  pass "T5.1 exit code 0 with uncommitted changes"
else
  fail "T5.1 exit code" "expected 0, got $RC"
fi

# Check if commit was made
LAST_MSG=$(git log -1 --format=%s 2>/dev/null)
if echo "$LAST_MSG" | grep -q "flight: auto-checkpoint"; then
  pass "T5.1 auto-checkpoint commit created"
else
  fail "T5.1 auto-checkpoint commit" "last msg: $LAST_MSG"
fi

# Check JSON output
if echo "$OUTPUT" | jq -e '.decision' > /dev/null 2>&1; then
  pass "T5.1 outputs valid JSON with decision field"
else
  fail "T5.1 JSON output" "got: $OUTPUT"
fi

# T5.2: Session ends with clean working tree
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false}' | bash "$PLUGIN_DIR/scripts/stop-checkpoint.sh" 2>&1)
RC=$?
if [ $RC -eq 0 ] && [ -z "$OUTPUT" ]; then
  pass "T5.2 clean tree — silent exit 0"
else
  fail "T5.2 clean tree" "rc=$RC, output=$OUTPUT"
fi

# T5.3: Session ends without FLIGHT_MODE.md
rm -f FLIGHT_MODE.md
echo "change" >> test.txt
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":false}' | bash "$PLUGIN_DIR/scripts/stop-checkpoint.sh" 2>&1)
RC=$?
if [ $RC -eq 0 ] && [ -z "$OUTPUT" ]; then
  pass "T5.3 no FLIGHT_MODE.md — silent no-op"
else
  fail "T5.3 no FLIGHT_MODE.md" "rc=$RC, output=$OUTPUT"
fi
git checkout -- test.txt 2>/dev/null || true

# T5.4: Hook with stop_hook_active=true (loop guard)
echo "# Flight Mode Active" > FLIGHT_MODE.md
echo "change2" >> test.txt
OUTPUT=$(echo '{"cwd":"'"$TEST_DIR"'","stop_hook_active":true}' | bash "$PLUGIN_DIR/scripts/stop-checkpoint.sh" 2>&1)
RC=$?
if [ $RC -eq 0 ] && [ -z "$OUTPUT" ]; then
  pass "T5.4 stop_hook_active=true — exits immediately (loop guard)"
else
  fail "T5.4 loop guard" "rc=$RC, output=$OUTPUT"
fi

# T5.5: Hook in non-git directory
NOGIT_DIR=$(mktemp -d)
echo "# Flight Mode Active" > "$NOGIT_DIR/FLIGHT_MODE.md"
OUTPUT=$(echo '{"cwd":"'"$NOGIT_DIR"'","stop_hook_active":false}' | bash "$PLUGIN_DIR/scripts/stop-checkpoint.sh" 2>&1)
RC=$?
rm -rf "$NOGIT_DIR"
if [ $RC -eq 0 ]; then
  pass "T5.5 non-git directory — graceful exit"
else
  fail "T5.5 non-git directory" "rc=$RC"
fi

# ═══════════════════════════════════════════════════
# T6: Context Monitor Hook (context-monitor.sh)
# ═══════════════════════════════════════════════════
section "T6: Context Monitor (context-monitor.sh)"

# Clean up any existing state files
rm -rf /tmp/flight-mode-* 2>/dev/null || true

# Need FLIGHT_MODE.md in test dir
echo "# Flight Mode Active" > "$TEST_DIR/FLIGHT_MODE.md"

# T6.1: Below threshold — silent
OUTPUT=$(printf '{"cwd":"%s","tool_name":"Bash","tool_output":"ok"}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" 2>&1)
RC=$?
if [ $RC -eq 0 ] && [ -z "$OUTPUT" ]; then
  pass "T6.1 below threshold — silent (zero context overhead)"
else
  fail "T6.1 below threshold" "rc=$RC, output=$OUTPUT"
fi

# T6.5: Without FLIGHT_MODE.md — no-op
rm -f "$TEST_DIR/FLIGHT_MODE.md"
OUTPUT=$(printf '{"cwd":"%s","tool_name":"Read","tool_output":"data"}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" 2>&1)
RC=$?
if [ $RC -eq 0 ] && [ -z "$OUTPUT" ]; then
  pass "T6.5 no FLIGHT_MODE.md — silent no-op"
else
  fail "T6.5 no FLIGHT_MODE.md" "rc=$RC, output=$OUTPUT"
fi

# Restore FLIGHT_MODE.md for remaining tests
echo "# Flight Mode Active" > "$TEST_DIR/FLIGHT_MODE.md"

# T6.6: State file persistence — counter increments
rm -rf /tmp/flight-mode-* 2>/dev/null || true
for i in $(seq 1 5); do
  printf '{"cwd":"%s","tool_name":"Read","tool_output":"line1\\nline2\\nline3"}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" > /dev/null 2>&1
done

STATE_FILE=$(ls /tmp/flight-mode-*/context.json 2>/dev/null | head -1)
if [ -n "$STATE_FILE" ]; then
  CALLS=$(jq -r '.tool_calls' "$STATE_FILE" 2>/dev/null)
  READS=$(jq -r '.file_reads' "$STATE_FILE" 2>/dev/null)
  if [ "$CALLS" = "5" ] && [ "$READS" = "5" ]; then
    pass "T6.6 state persistence — 5 calls tracked (tool_calls=$CALLS, file_reads=$READS)"
  else
    fail "T6.6 state persistence" "expected calls=5 reads=5, got calls=$CALLS reads=$READS"
  fi
else
  fail "T6.6 state file" "not created"
fi

# T6.2-T6.4: Threshold warnings
# Simulate many calls to reach thresholds
rm -rf /tmp/flight-mode-* 2>/dev/null || true

# Manually seed state to simulate 45% threshold (~27 tool calls with no reads)
STATE_FILE_DIR="/tmp/flight-mode-test-threshold-$$"
mkdir -p "$STATE_FILE_DIR"

# Determine the hash so we know which state file to seed
if command -v md5 >/dev/null 2>&1; then
  DIR_HASH=$(echo -n "$TEST_DIR" | md5)
elif command -v md5sum >/dev/null 2>&1; then
  DIR_HASH=$(echo -n "$TEST_DIR" | md5sum | cut -c1-12)
else
  DIR_HASH=$(echo -n "$TEST_DIR" | cksum | cut -d' ' -f1)
fi
REAL_STATE_DIR="/tmp/flight-mode-${DIR_HASH}"
mkdir -p "$REAL_STATE_DIR"

# T6.2: ~50% threshold (tool_calls * 2.5 / 1.5 ≈ 45-60 → need ~27 calls)
echo '{"tool_calls": 26, "file_reads": 10, "lines_read": 100}' > "$REAL_STATE_DIR/context.json"
OUTPUT=$(printf '{"cwd":"%s","tool_name":"Bash","tool_output":"ok"}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" 2>&1)
if echo "$OUTPUT" | grep -qi "consider checkpointing"; then
  pass "T6.2 ~45% threshold — 'consider checkpointing' warning"
else
  fail "T6.2 ~45% threshold" "output: $OUTPUT"
fi

# T6.3: ~70% threshold (need ~39 calls)
echo '{"tool_calls": 38, "file_reads": 15, "lines_read": 200}' > "$REAL_STATE_DIR/context.json"
OUTPUT=$(printf '{"cwd":"%s","tool_name":"Bash","tool_output":"ok"}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" 2>&1)
if echo "$OUTPUT" | grep -qi "checkpoint now"; then
  pass "T6.3 ~65% threshold — 'Checkpoint NOW' warning"
else
  fail "T6.3 ~65% threshold" "output: $OUTPUT"
fi

# T6.4: ~85% threshold (need ~51 calls)
echo '{"tool_calls": 50, "file_reads": 20, "lines_read": 300}' > "$REAL_STATE_DIR/context.json"
OUTPUT=$(printf '{"cwd":"%s","tool_name":"Bash","tool_output":"ok"}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" 2>&1)
if echo "$OUTPUT" | grep -qi "stop"; then
  pass "T6.4 ~85% threshold — 'STOP' warning"
else
  fail "T6.4 ~85% threshold" "output: $OUTPUT"
fi

# T6.7: Timeout test (should complete well under 5s)
START_TIME=$(date +%s)
printf '{"cwd":"%s","tool_name":"Read","tool_output":"data"}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" > /dev/null 2>&1
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
if [ "$ELAPSED" -lt 5 ]; then
  pass "T6.7 completes within timeout (${ELAPSED}s < 5s)"
else
  fail "T6.7 timeout" "took ${ELAPSED}s"
fi

# T6.8: Counter reset (new state dir = fresh)
rm -rf "$REAL_STATE_DIR"
OUTPUT=$(printf '{"cwd":"%s","tool_name":"Bash","tool_output":"ok"}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" 2>&1)
if [ -z "$OUTPUT" ]; then
  pass "T6.8 fresh session — counters reset, silent"
else
  fail "T6.8 counter reset" "unexpected output: $OUTPUT"
fi

# ═══════════════════════════════════════════════════
# T7: Profile Lookup (data validation)
# ═══════════════════════════════════════════════════
section "T7: Profile Data Validation"

PROFILES="$PLUGIN_DIR/data/flight-profiles.md"

# T7.1: Known carriers exist in lookup table
for CARRIER in "Delta" "United" "Cathay Pacific" "Air France" "Emirates" "Singapore Airlines"; do
  if grep -q "$CARRIER" "$PROFILES"; then
    pass "T7.1 '$CARRIER' found in profiles"
  else
    fail "T7.1 '$CARRIER' in profiles" "not found"
  fi
done

# T7.2: Rating scale values present
for RATING in "EXCELLENT" "GOOD" "USABLE" "CHOPPY" "POOR" "UNKNOWN"; do
  if grep -q "$RATING" "$PROFILES"; then
    pass "T7.2 rating '$RATING' defined"
  else
    fail "T7.2 rating '$RATING'" "not found"
  fi
done

# T7.3: UNKNOWN/Default fallback exists
if grep -q "UNKNOWN" "$PROFILES"; then
  pass "T7.3 UNKNOWN fallback profile exists"
else
  fail "T7.3 UNKNOWN fallback" "missing"
fi

# T7.4: Route patterns table exists
if grep -q "Route Patterns" "$PROFILES" && grep -q "Transpacific" "$PROFILES"; then
  pass "T7.4 route patterns table with key routes"
else
  fail "T7.4 route patterns" "table missing or incomplete"
fi

# T7.5: Quick Lookup Table has expected columns
if grep -q "| Carrier | Rating (domestic) | Rating (long-haul) | Stable Window | Key Note |" "$PROFILES"; then
  pass "T7.5 lookup table has all required columns"
else
  fail "T7.5 lookup table columns" "header mismatch"
fi

# ═══════════════════════════════════════════════════
# T8: Edge Cases
# ═══════════════════════════════════════════════════
section "T8: Edge Cases"

# T8.5: jq dependency check
if command -v jq >/dev/null 2>&1; then
  pass "T8.5a jq is installed"
else
  fail "T8.5a jq installed" "not found — hooks will fail"
fi

# T8.5b: What happens if jq gets bad input
BAD_OUTPUT=$(echo "not json at all" | jq -r '.tool_name // ""' 2>/dev/null || echo "HANDLED")
if [ "$BAD_OUTPUT" = "HANDLED" ] || [ -z "$BAD_OUTPUT" ]; then
  pass "T8.5b jq handles bad input gracefully"
else
  fail "T8.5b jq bad input" "unexpected: $BAD_OUTPUT"
fi

# T8.6: Stop hook with empty JSON input
OUTPUT=$(echo '{}' | bash "$PLUGIN_DIR/scripts/stop-checkpoint.sh" 2>&1)
RC=$?
if [ $RC -eq 0 ]; then
  pass "T8.6 stop hook with empty JSON — exits cleanly"
else
  fail "T8.6 empty JSON" "rc=$RC"
fi

# T8.7: Context monitor with empty JSON
OUTPUT=$(echo '{}' | bash "$PLUGIN_DIR/scripts/context-monitor.sh" 2>&1)
RC=$?
if [ $RC -eq 0 ]; then
  pass "T8.7 context monitor with empty JSON — exits cleanly"
else
  fail "T8.7 empty JSON" "rc=$RC"
fi

# T8.8: SKILL.md references CLAUDE_PLUGIN_ROOT variable
if grep -q 'CLAUDE_PLUGIN_ROOT' "$PLUGIN_DIR/skills/flight-on/SKILL.md"; then
  pass "T8.8 flight-on references CLAUDE_PLUGIN_ROOT for portable paths"
else
  fail "T8.8 CLAUDE_PLUGIN_ROOT" "not found in flight-on skill"
fi

# T8.9: hooks.json references CLAUDE_PLUGIN_ROOT
if grep -q 'CLAUDE_PLUGIN_ROOT' "$PLUGIN_DIR/hooks/hooks.json"; then
  pass "T8.9 hooks.json uses CLAUDE_PLUGIN_ROOT for script paths"
else
  fail "T8.9 CLAUDE_PLUGIN_ROOT in hooks.json" "not found"
fi

# T8.10: flight-on skill has all protocol rules
for RULE in "Rule 1" "Rule 2" "Rule 3" "Rule 4" "Rule 5" "Rule 6" "Rule 7"; do
  if grep -q "$RULE" "$PLUGIN_DIR/skills/flight-on/SKILL.md"; then
    pass "T8.10 flight-on has $RULE"
  else
    fail "T8.10 $RULE in flight-on" "missing"
  fi
done

# T8.11: flight-off has squash approach
if grep -q "git reset --soft" "$PLUGIN_DIR/skills/flight-off/SKILL.md"; then
  pass "T8.11 flight-off uses non-interactive squash (git reset --soft)"
else
  fail "T8.11 non-interactive squash" "not found in flight-off"
fi

# T8.12: flight-on has calibration table for all ratings
for RATING in "EXCELLENT" "GOOD" "USABLE" "CHOPPY" "POOR" "UNKNOWN"; do
  if grep -q "| $RATING" "$PLUGIN_DIR/skills/flight-on/SKILL.md"; then
    pass "T8.12 calibration table has $RATING"
  else
    fail "T8.12 calibration for $RATING" "missing from table"
  fi
done

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
  log "${GREEN}All tests passed!${NC}"
else
  log "${RED}$FAIL test(s) failed — see details above${NC}"
fi

# Clean up
rm -rf /tmp/flight-mode-* 2>/dev/null || true

exit $FAIL
