#!/bin/bash
# Conditional Stop hook — only reminds about TRACES/LEARNINGS/Roadmap
# when tracked files were modified but traces weren't updated.
# Uses exit 2 + stderr to inject reminder into Claude's context.
# Exit 0 = Claude stops normally. Exit 2 = Claude continues with stderr as context.
#
# Exemptions (hardcoded): TRACES.md, LEARNINGS.md, ROADMAP.md (enforced targets),
#   .claude/sync/ (auto-modified by sync hooks), untracked files.
# Exemptions (configurable): .claude/traces-exempt.txt (one filename per line).

# jq is required for parsing hook input JSON
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)

# Break infinite loop: if Stop hook is already active, let Claude stop
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ]; then
  exit 0
fi

cd "$CWD" 2>/dev/null || exit 0

# Build exemption regex from hardcoded defaults + project-specific file
EXEMPT="TRACES\.md|LEARNINGS\.md|ROADMAP\.md"
EXEMPT_FILE=".claude/traces-exempt.txt"
if [ -f "$EXEMPT_FILE" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    # Escape dots for regex
    ESCAPED=$(echo "$line" | sed 's/\./\\./g')
    EXEMPT="${EXEMPT}|${ESCAPED}"
  done < "$EXEMPT_FILE"
fi

# Check if any tracked files were modified (staged or unstaged)
# Exclude: untracked files (??), .claude/sync/ (auto-modified by hooks), exempt files
CODE_CHANGES=$(git status --porcelain 2>/dev/null \
  | grep -vE '^\?\?' \
  | grep -vF '.claude/sync/' \
  | grep -vE "($EXEMPT)")

# If no tracked files changed (after exemptions), no reminder needed
if [ -z "$CODE_CHANGES" ]; then
  exit 0
fi

# Check if TRACES.md was updated AFTER the newest changed file
# Compares file modification times instead of using a fixed window,
# so changes made after a TRACES.md update are always caught
if [ -f "TRACES.md" ]; then
  TRACES_MOD=$(stat -f %m "TRACES.md" 2>/dev/null || stat -c %Y "TRACES.md" 2>/dev/null || echo 0)
  NEWEST_CODE_MOD=0
  COUNT=0
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    FILE="${entry:3}"
    [ -f "$FILE" ] || continue
    MOD=$(stat -f %m "$FILE" 2>/dev/null || stat -c %Y "$FILE" 2>/dev/null || echo 0)
    [ "${MOD:-0}" -gt "$NEWEST_CODE_MOD" ] && NEWEST_CODE_MOD="${MOD:-0}"
    COUNT=$((COUNT + 1))
    [ "$COUNT" -ge 5 ] && break
  done <<< "$CODE_CHANGES"

  # If TRACES.md is newer than all checked changes, no reminder needed
  if [ "${TRACES_MOD:-0}" -ge "$NEWEST_CODE_MOD" ] && [ "$NEWEST_CODE_MOD" -gt 0 ]; then
    exit 0
  fi
fi

# Build reminder listing what needs updating
REMIND=""
if [ -f "TRACES.md" ]; then
  REMIND="${REMIND}(1) Add an iteration entry to TRACES.md. "
else
  REMIND="${REMIND}(1) Create TRACES.md and add an iteration entry (run /setup-cash-build-system if not yet set up). "
fi

NOW=$(date +%s)
if [ -f "ROADMAP.md" ]; then
  ROADMAP_MOD=$(stat -f %m "ROADMAP.md" 2>/dev/null || stat -c %Y "ROADMAP.md" 2>/dev/null || echo 0)
  DIFF=$((NOW - ${ROADMAP_MOD:-0}))
  if [ "$DIFF" -ge 3600 ]; then
    REMIND="${REMIND}(2) Update ROADMAP.md with current status. "
  fi
fi

REMIND="${REMIND}(3) Log any trial-and-error patterns to LEARNINGS.md."

# Files were modified but TRACES.md wasn't updated — exit 2 so Claude continues
# stderr is fed to Claude as context (per hooks reference: Stop exit 2 = continue with stderr)
echo "Session check: Code files were modified but TRACES.md was not updated. Before stopping: ${REMIND}" >&2

exit 2
