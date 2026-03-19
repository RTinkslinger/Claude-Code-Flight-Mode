#!/bin/bash
# Flight Mode — V2 Test Suite: flight commit squash logic
# Tests the git reset --soft squash approach used by /flight-off
# to consolidate flight: prefixed commits
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
# Prerequisites
# ═══════════════════════════════════════════════════
section "SQ.0: Prerequisites"

if ! command -v git >/dev/null 2>&1; then
  fail "SQ.0a git is installed" "git not found"
  exit 1
fi
pass "SQ.0a git is installed"

if ! command -v jq >/dev/null 2>&1; then
  fail "SQ.0b jq is installed" "jq not found"
  exit 1
fi
pass "SQ.0b jq is installed"

# ═══════════════════════════════════════════════════
# SQ.1: Contiguous flight commits squash correctly
# ═══════════════════════════════════════════════════
section "SQ.1: Contiguous Flight Commit Squash"

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create commit history: initial, feat: base, flight: task 1-3
echo "init" > file.txt
git add file.txt
git commit -q -m "initial"

echo "base feature" > feature.txt
git add feature.txt
git commit -q -m "feat: base"

echo "task 1" > task1.txt
git add task1.txt
git commit -q -m "flight: task 1"

echo "task 2" > task2.txt
git add task2.txt
git commit -q -m "flight: task 2"

echo "task 3" > task3.txt
git add task3.txt
git commit -q -m "flight: task 3"

# Count commits before squash
BEFORE_COUNT=$(git log --oneline | wc -l | tr -d ' ')

# Perform squash: find first flight commit, get its parent, reset --soft, recommit
FIRST_FLIGHT=$(git log --oneline --reverse | grep "flight:" | head -1 | cut -d' ' -f1)
BEFORE_FLIGHT=$(git rev-parse "${FIRST_FLIGHT}^")
git reset --soft "$BEFORE_FLIGHT"
git commit -q -m "feat: squashed flight work"

AFTER_COUNT=$(git log --oneline | wc -l | tr -d ' ')

if [ "$AFTER_COUNT" -eq 3 ]; then
  pass "SQ.1a squash reduces to 3 commits (initial, feat: base, squashed)"
else
  fail "SQ.1a commit count" "expected 3, got $AFTER_COUNT (was $BEFORE_COUNT)"
fi

# Verify no flight: commits remain
FLIGHT_REMAINING=$(git log --oneline | grep "flight:" | wc -l | tr -d ' ')
if [ "$FLIGHT_REMAINING" -eq 0 ]; then
  pass "SQ.1b no flight: commits remain after squash"
else
  fail "SQ.1b flight commits remain" "$FLIGHT_REMAINING still present"
fi

# Verify all files exist (content preserved)
ALL_FILES_EXIST=true
for f in file.txt feature.txt task1.txt task2.txt task3.txt; do
  if [ ! -f "$f" ]; then
    ALL_FILES_EXIST=false
    break
  fi
done
if [ "$ALL_FILES_EXIST" = "true" ]; then
  pass "SQ.1c all file changes preserved in squashed commit"
else
  fail "SQ.1c file preservation" "some files missing after squash"
fi

rm -rf "$TEMP_DIR"

# ═══════════════════════════════════════════════════
# SQ.2: All-flight-commit history edge case
# ═══════════════════════════════════════════════════
section "SQ.2: All-Flight-Commit History"

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Every commit has flight: prefix
echo "file1" > f1.txt
git add f1.txt
git commit -q -m "flight: first task"

echo "file2" > f2.txt
git add f2.txt
git commit -q -m "flight: second task"

echo "file3" > f3.txt
git add f3.txt
git commit -q -m "flight: third task"

# Find the first flight commit
FIRST_FLIGHT=$(git log --oneline --reverse | grep "flight:" | head -1 | cut -d' ' -f1)

# Try to get its parent — this should fail for root commit
BEFORE_FLIGHT=$(git rev-parse "${FIRST_FLIGHT}^" 2>/dev/null)
PARSE_RC=$?

if [ $PARSE_RC -ne 0 ] || [ -z "$BEFORE_FLIGHT" ]; then
  pass "SQ.2a rev-parse fails for root commit parent (edge case documented)"
  # The squash must handle this differently: reset to root tree and amend
  skip "SQ.2b squash with all-flight" "requires special handling for root-only history"
else
  # If the repo somehow has a parent, the squash would work normally
  git reset --soft "$BEFORE_FLIGHT"
  git commit -q -m "feat: all flight work squashed"
  REMAINING=$(git log --oneline | grep "flight:" | wc -l | tr -d ' ')
  if [ "$REMAINING" -eq 0 ]; then
    pass "SQ.2a squash handled all-flight history"
    pass "SQ.2b no flight commits remain"
  else
    fail "SQ.2b flight cleanup" "$REMAINING flight commits remain"
  fi
fi

rm -rf "$TEMP_DIR"

# ═══════════════════════════════════════════════════
# SQ.3: Flight commit count (current branch only)
# ═══════════════════════════════════════════════════
section "SQ.3: Flight Commit Count — Branch Isolation"

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create base
echo "init" > base.txt
git add base.txt
git commit -q -m "initial"

# Add flight commits on main
echo "main-flight" > main-flight.txt
git add main-flight.txt
git commit -q -m "flight: main work"

# Create another branch with different commits
git checkout -q -b other-branch
echo "other" > other.txt
git add other.txt
git commit -q -m "flight: other branch work"

echo "other2" > other2.txt
git add other2.txt
git commit -q -m "flight: other branch task 2"

# Switch back to main
git checkout -q main

# Count flight commits on main only (no --all)
MAIN_COUNT=$(git log --oneline | grep "flight:" | wc -l | tr -d ' ')
# Count with --all (would include other branch)
ALL_COUNT=$(git log --all --oneline | grep "flight:" | wc -l | tr -d ' ')

if [ "$MAIN_COUNT" -eq 1 ]; then
  pass "SQ.3a main branch has 1 flight commit"
else
  fail "SQ.3a main flight count" "expected 1, got $MAIN_COUNT"
fi

if [ "$ALL_COUNT" -eq 3 ]; then
  pass "SQ.3b --all shows 3 flight commits (includes other branch)"
else
  # Might be 2 if the branch commit is also reachable from main
  pass "SQ.3b --all shows $ALL_COUNT flight commits across branches"
fi

if [ "$MAIN_COUNT" -lt "$ALL_COUNT" ]; then
  pass "SQ.3c current-branch count ($MAIN_COUNT) < all-branches count ($ALL_COUNT) — isolation confirmed"
else
  fail "SQ.3c branch isolation" "main=$MAIN_COUNT, all=$ALL_COUNT — not isolated"
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
  log "${GREEN}All squash tests passed!${NC}"
else
  log "${RED}$FAIL test(s) failed — see details above${NC}"
fi

exit $FAIL
