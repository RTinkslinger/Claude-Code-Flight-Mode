#!/bin/bash
# Conditional Stop hook — only reminds about TRACES/LEARNINGS/Roadmap
# when code files were modified but traces weren't updated.
# Uses exit 2 + stderr to inject reminder into Claude's context.
# Exit 0 = Claude stops normally. Exit 2 = Claude continues with stderr as context.

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

# Check if any code files were modified (staged, unstaged, or untracked)
# Exclude TRACES.md, LEARNINGS.md, CLAUDE.md, .claude/, and other non-code files
CODE_CHANGES=$(git status --porcelain 2>/dev/null | grep -vE '(TRACES\.md|LEARNINGS\.md|CLAUDE\.md|\.claude/|\.md |\.txt )' | grep -vE '^\?\?' | head -1)

# If no code files changed, no reminder needed
if [ -z "$CODE_CHANGES" ]; then
  exit 0
fi

# Check if TRACES.md was updated in this session (modified time within last hour)
if [ -f "TRACES.md" ]; then
  TRACES_MOD=$(stat -f %m "TRACES.md" 2>/dev/null || stat -c %Y "TRACES.md" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  DIFF=$((NOW - ${TRACES_MOD:-0}))
  if [ "$DIFF" -lt 3600 ]; then
    exit 0  # TRACES.md was recently updated, no reminder needed
  fi
fi

# Code was modified but TRACES.md wasn't updated — exit 2 so Claude continues
# stderr is fed to Claude as context (per hooks reference: Stop exit 2 = continue with stderr)
echo "Session check: Code files were modified but TRACES.md was not updated. Before stopping: (1) Add an iteration entry to TRACES.md, (2) Log any trial-and-error patterns to LEARNINGS.md, (3) Update Build Roadmap status." >&2

exit 2
