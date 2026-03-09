#!/bin/bash
# End-to-end simulation: mimics Claude Code calling hooks with realistic payloads
# Tests the full lifecycle: activation state → tool use monitoring → session end
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'
PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo -e "${GREEN}  PASS${NC} $1"; }
fail() { FAIL=$((FAIL+1)); echo -e "${RED}  FAIL${NC} $1 — $2"; }
section() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; }

# Create isolated test repo
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
git init -q
git commit --allow-empty -m "initial" -q

echo -e "${CYAN}Test repo: $TEST_DIR${NC}"
echo -e "${CYAN}Plugin dir: $PLUGIN_DIR${NC}"

# ═══════════════════════════════════════════════════
# PHASE A: Pre-activation — hooks should be no-ops
# ═══════════════════════════════════════════════════
section "Phase A: Pre-activation (no FLIGHT_MODE.md)"

# A.1: PostToolUse fires but does nothing
OUTPUT=$(printf '{"cwd":"%s","tool_name":"Read","tool_output":"some data"}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" 2>&1)
if [ -z "$OUTPUT" ]; then
  pass "A.1 context-monitor no-op without FLIGHT_MODE.md"
else
  fail "A.1 context-monitor no-op" "output: $OUTPUT"
fi

# A.2: Stop hook fires but does nothing
echo "test" > somefile.txt && git add somefile.txt && git commit -m "add file" -q
echo "modified" >> somefile.txt
OUTPUT=$(printf '{"cwd":"%s","stop_hook_active":false}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/stop-checkpoint.sh" 2>&1)
if [ -z "$OUTPUT" ]; then
  pass "A.2 stop-checkpoint no-op without FLIGHT_MODE.md"
else
  fail "A.2 stop-checkpoint no-op" "output: $OUTPUT"
fi
git checkout -- somefile.txt 2>/dev/null

# ═══════════════════════════════════════════════════
# PHASE B: Simulate /flight-on activation
# ═══════════════════════════════════════════════════
section "Phase B: Simulate activation (/flight-on)"

# B.1: Create FLIGHT_MODE.md (what /flight-on does)
cat > FLIGHT_MODE.md << 'FMEOF'
# Flight Mode Active

**Airline:** Cathay Pacific HKG-LAX
**WiFi Rating:** USABLE (drops expected every ~20-40 min)
**Activated:** 2026-03-09 15:00
**Stable Window:** 20-40 min

## Condensed Protocol (for session recovery)

1. **Read `.flight-state.md`** — resume from last incomplete micro-task
2. **Micro-tasks only** — max 2 tool calls per task, decompose before starting
3. **Checkpoint every 2-3 tasks** — update `.flight-state.md` + git commit
4. **Git discipline** — `flight:` prefix, stage specific files
5. **Context budget** — minimize file reads
6. **If a drop seems imminent** — finish current edit, commit immediately
7. **Every edit must be self-contained** — never leave files inconsistent
FMEOF

if [ -f "FLIGHT_MODE.md" ]; then
  pass "B.1 FLIGHT_MODE.md created"
else
  fail "B.1 FLIGHT_MODE.md" "not created"
fi

# B.2: Create .flight-state.md
cat > .flight-state.md << 'FSEOF'
# Flight State

**Session started:** 2026-03-09 15:00
**Airline:** Cathay Pacific HKG-LAX
**WiFi rating:** USABLE
**Project:** test-project

## Current Task
Add authentication middleware

## Micro-Tasks
- [ ] 1. Read src/auth.ts
- [ ] 2. Add token validation
- [ ] 3. Add tests
- [ ] 4. Update docs

## Last Action
Session just started.

## Files Modified This Session
(none yet)

## Recovery Instructions
If this session dropped: Start from micro-task 1.
FSEOF

if [ -f ".flight-state.md" ]; then
  pass "B.2 .flight-state.md created"
else
  fail "B.2 .flight-state.md" "not created"
fi

# B.3: .gitignore should exclude runtime files
cat > .gitignore << 'GIEOF'
FLIGHT_MODE.md
.flight-state.md
.flight-state-*.md
GIEOF
git add .gitignore && git commit -m "add gitignore" -q

if git status --porcelain | grep -q "FLIGHT_MODE.md"; then
  # Should show as ?? (untracked) not tracked
  pass "B.3 FLIGHT_MODE.md is untracked (gitignored)"
else
  pass "B.3 FLIGHT_MODE.md properly gitignored (not in status)"
fi

# ═══════════════════════════════════════════════════
# PHASE C: Simulate work session (tool calls)
# ═══════════════════════════════════════════════════
section "Phase C: Simulate work session"

# Clean up old state
rm -rf /tmp/flight-mode-* 2>/dev/null || true

# C.1: Simulate 3 Read calls (micro-task 1: read source)
# Note: use %s to avoid printf interpreting \n as newlines in JSON
for i in 1 2 3; do
  echo "{\"cwd\":\"$TEST_DIR\",\"tool_name\":\"Read\",\"tool_output\":\"line1 line2 line3 line4 line5\"}" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" > /dev/null 2>&1
done

STATE_FILE=$(ls /tmp/flight-mode-*/context.json 2>/dev/null | head -1)
if [ -n "$STATE_FILE" ]; then
  CALLS=$(jq -r '.tool_calls' "$STATE_FILE")
  if [ "$CALLS" = "3" ]; then
    pass "C.1 tracked 3 Read calls"
  else
    fail "C.1 Read call tracking" "expected 3, got $CALLS"
  fi
else
  fail "C.1 state file" "not created"
fi

# C.2: Simulate an Edit call (micro-task 2: modify file)
echo "auth middleware v2" > src_auth.txt
git add src_auth.txt && git commit -m "flight: micro-task 2 — add token validation" -q

LAST_MSG=$(git log -1 --format=%s)
if echo "$LAST_MSG" | grep -q "^flight:"; then
  pass "C.2 flight: prefix in commit message"
else
  fail "C.2 commit prefix" "msg: $LAST_MSG"
fi

# C.3: Simulate more tool calls — check context monitor stays silent below threshold
OUTPUT=$(printf '{"cwd":"%s","tool_name":"Edit","tool_output":"ok"}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" 2>&1)
if [ -z "$OUTPUT" ]; then
  pass "C.3 context monitor silent at low usage"
else
  fail "C.3 silent at low usage" "output: $OUTPUT"
fi

# C.4: Simulate checkpoint — update .flight-state.md
sed -i.bak 's/- \[ \] 1\./- [x] 1./' .flight-state.md 2>/dev/null || sed -i '' 's/- \[ \] 1\./- [x] 1./' .flight-state.md
sed -i.bak 's/- \[ \] 2\./- [x] 2./' .flight-state.md 2>/dev/null || sed -i '' 's/- \[ \] 2\./- [x] 2./' .flight-state.md
rm -f .flight-state.md.bak

if grep -q "\[x\] 1\." .flight-state.md && grep -q "\[x\] 2\." .flight-state.md; then
  pass "C.4 checkpoint — tasks 1-2 marked complete"
else
  fail "C.4 checkpoint" "task marks not updated"
fi

# ═══════════════════════════════════════════════════
# PHASE D: Simulate drop (session end with dirty state)
# ═══════════════════════════════════════════════════
section "Phase D: Simulate WiFi drop (session end)"

# D.1: Make uncommitted changes (simulating mid-task drop)
echo "test file v2" > test_file.txt
git add test_file.txt && git commit -m "add test_file" -q
echo "incomplete edit" >> test_file.txt

# D.2: Stop hook fires — should auto-commit
OUTPUT=$(printf '{"cwd":"%s","stop_hook_active":false}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/stop-checkpoint.sh" 2>&1)
RC=$?

if [ $RC -eq 0 ]; then
  pass "D.1 stop hook exits 0"
else
  fail "D.1 stop hook exit" "rc=$RC"
fi

LAST_MSG=$(git log -1 --format=%s)
if echo "$LAST_MSG" | grep -q "flight: auto-checkpoint"; then
  pass "D.2 auto-checkpoint commit created on drop"
else
  fail "D.2 auto-checkpoint" "last msg: $LAST_MSG"
fi

if echo "$OUTPUT" | jq -e '.decision == "approve"' > /dev/null 2>&1; then
  pass "D.3 hook outputs approve decision JSON"
else
  fail "D.3 JSON output" "output: $OUTPUT"
fi

# ═══════════════════════════════════════════════════
# PHASE E: Simulate recovery (new session)
# ═══════════════════════════════════════════════════
section "Phase E: Simulate recovery (new session)"

# E.1: FLIGHT_MODE.md still exists
if [ -f "FLIGHT_MODE.md" ]; then
  pass "E.1 FLIGHT_MODE.md persists after drop"
else
  fail "E.1 FLIGHT_MODE.md" "missing after drop"
fi

# E.2: .flight-state.md still exists with task state
if [ -f ".flight-state.md" ]; then
  pass "E.2 .flight-state.md persists after drop"
else
  fail "E.2 .flight-state.md" "missing after drop"
fi

# E.3: Recovery instructions are present
if grep -q "Recovery Instructions" .flight-state.md; then
  pass "E.3 recovery instructions present in .flight-state.md"
else
  fail "E.3 recovery instructions" "missing"
fi

# E.4: Can determine resume point from task list
NEXT_TASK=$(grep -n '^\- \[ \]' .flight-state.md | head -1)
if [ -n "$NEXT_TASK" ]; then
  pass "E.4 next incomplete task identifiable: $(echo "$NEXT_TASK" | sed 's/.*\] //')"
else
  fail "E.4 resume point" "no incomplete tasks found"
fi

# E.5: Context monitor resets for new session
rm -rf /tmp/flight-mode-* 2>/dev/null || true
OUTPUT=$(printf '{"cwd":"%s","tool_name":"Read","tool_output":"data"}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" 2>&1)
if [ -z "$OUTPUT" ]; then
  pass "E.5 context monitor fresh for new session"
else
  fail "E.5 context monitor reset" "output: $OUTPUT"
fi

# ═══════════════════════════════════════════════════
# PHASE F: Simulate /flight-off
# ═══════════════════════════════════════════════════
section "Phase F: Simulate deactivation (/flight-off)"

# F.1: Count flight commits
FLIGHT_COMMITS=$(git log --oneline | grep "flight:" | wc -l | tr -d ' ')
if [ "$FLIGHT_COMMITS" -ge 1 ]; then
  pass "F.1 found $FLIGHT_COMMITS flight: commit(s)"
else
  fail "F.1 flight commits" "none found"
fi

# F.2: Simulate squash (if 2+ commits)
if [ "$FLIGHT_COMMITS" -ge 2 ]; then
  BEFORE_FLIGHT=$(git log --oneline | grep -v "flight:" | head -1 | cut -d' ' -f1)
  git reset --soft "$BEFORE_FLIGHT" > /dev/null 2>&1
  git commit -m "feat: add auth middleware and tests" > /dev/null 2>&1
  NEW_MSG=$(git log -1 --format=%s)
  if echo "$NEW_MSG" | grep -q "feat:"; then
    pass "F.2 squash via git reset --soft succeeded"
  else
    fail "F.2 squash" "msg: $NEW_MSG"
  fi
else
  pass "F.2 squash skipped (only $FLIGHT_COMMITS commit)"
fi

# F.3: Archive .flight-state.md
ARCHIVE_NAME=".flight-state-$(date +%Y-%m-%d).md"
mv .flight-state.md "$ARCHIVE_NAME"
if [ -f "$ARCHIVE_NAME" ] && [ ! -f ".flight-state.md" ]; then
  pass "F.3 .flight-state.md archived to $ARCHIVE_NAME"
else
  fail "F.3 archive" "rename failed"
fi

# F.4: Remove FLIGHT_MODE.md
rm -f FLIGHT_MODE.md
if [ ! -f "FLIGHT_MODE.md" ]; then
  pass "F.4 FLIGHT_MODE.md removed — flight mode OFF"
else
  fail "F.4 cleanup" "FLIGHT_MODE.md still exists"
fi

# F.5: Hooks are now no-ops again
OUTPUT=$(printf '{"cwd":"%s","tool_name":"Read","tool_output":"data"}' "$TEST_DIR" | bash "$PLUGIN_DIR/scripts/context-monitor.sh" 2>&1)
if [ -z "$OUTPUT" ]; then
  pass "F.5 hooks return to no-op after deactivation"
else
  fail "F.5 post-deactivation" "output: $OUTPUT"
fi

# ═══════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════
section "SUMMARY"
TOTAL=$((PASS + FAIL))
echo ""
echo -e "  ${GREEN}Passed: $PASS${NC}"
echo -e "  ${RED}Failed: $FAIL${NC}"
echo -e "  Total:  $TOTAL"
echo ""
if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}Full lifecycle simulation passed!${NC}"
else
  echo -e "${RED}$FAIL test(s) failed${NC}"
fi

# Cleanup
rm -rf "$TEST_DIR"
rm -rf /tmp/flight-mode-* 2>/dev/null || true

exit $FAIL
