#!/bin/bash
# stop-check.sh — CASH Build System v1.3
# Reminds Claude to update TRACES.md when tracked files were modified.
# Exit 0 = let Claude stop. Exit 2 = block + remind (stderr fed to Claude).
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)

STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ]; then
  exit 0
fi

cd "$CWD" 2>/dev/null || exit 0

# --- Exemption list ---
EXEMPT="TRACES\.md|LEARNINGS\.md|ROADMAP\.md"
EXEMPT_FILE=".claude/traces-exempt.txt"
if [ -f "$EXEMPT_FILE" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    ESCAPED=$(echo "$line" | sed 's/\./\\./g')
    EXEMPT="${EXEMPT}|${ESCAPED}"
  done < "$EXEMPT_FILE"
fi

# --- Check for tracked file changes ---
CODE_CHANGES=$(git status --porcelain 2>/dev/null \
  | grep -vE '^\?\?' \
  | grep -vF '.claude/sync/' \
  | grep -vE "($EXEMPT)")

if [ -z "$CODE_CHANGES" ]; then
  exit 0
fi

# --- Auto-create TRACES.md scaffold if missing ---
if [ ! -f "TRACES.md" ]; then
  cat > TRACES.md << 'SCAFFOLD'
# Build Traces

## Project Summary
*No milestones yet.*

## Milestone Index
| # | Iterations | Focus | Key Decisions |
|---|------------|-------|---------------|

## Current Work
SCAFFOLD
fi

# --- Check 1: TRACES.md already modified (tracked) in working tree ---
# Exclude untracked (??) — the auto-created scaffold doesn't count
TRACES_MODIFIED=$(git status --porcelain 2>/dev/null | grep -vE '^\?\?' | grep -E "TRACES\.md$" || true)
if [ -n "$TRACES_MODIFIED" ]; then
  exit 0
fi

# --- Check 2: Session marker — prevent cascade after reminder ---
MARKER=""
if [ -n "$SESSION_ID" ]; then
  MARKER="/tmp/stop-check-${SESSION_ID}"
  if [ -f "$MARKER" ] && [ "TRACES.md" -nt "$MARKER" ]; then
    # We already reminded this session, and TRACES.md was updated since
    exit 0
  fi
fi

# --- Remind ---
echo "Session check: Files were modified but TRACES.md was not updated. Add an iteration entry before stopping." >&2

# Create/update session marker
if [ -n "$MARKER" ]; then
  touch "$MARKER"
fi

exit 2
