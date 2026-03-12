#!/bin/bash
# CC↔CAI Sync: SessionStart hook — pull latest state + check inbox
# Type: command | Event: SessionStart | Matcher: startup
#
# Fires alongside Cash Build System startup hook. Pulls latest sync state
# from remote, checks inbox for unacknowledged CAI messages, and outputs
# a summary to Claude's context.
#
# Exit codes: Always 0 — sync failure never blocks session start.
# Dependencies: jq, git

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0
cd "$CWD" 2>/dev/null || exit 0

# Only run if sync is initialized
[ -d ".claude/sync" ] || exit 0
[ -f ".claude/sync/state.json" ] || exit 0

# Clear push marker from previous session
rm -f ".claude/sync/.last-push"

# Pull latest sync state (fast-forward only, don't block on conflicts)
git pull --ff-only --quiet 2>/dev/null

# Check inbox for unacknowledged CAI messages
INBOX=".claude/sync/inbox.jsonl"
[ -f "$INBOX" ] || exit 0

# Find messages from CAI that haven't been acknowledged
# An ack message has type "ack" and references the original message ID
UNREAD=$(jq -c 'select(.source == "cai" and .type != "ack")' "$INBOX" 2>/dev/null | while read -r MSG; do
  MSG_ID=$(echo "$MSG" | jq -r '.id')
  # Check if there's an ack for this message
  ACK_EXISTS=$(jq -c "select(.type == \"ack\" and .context.references[]? == \"$MSG_ID\")" "$INBOX" 2>/dev/null)
  if [ -z "$ACK_EXISTS" ]; then
    echo "$MSG"
  fi
done)

if [ -n "$UNREAD" ]; then
  COUNT=$(echo "$UNREAD" | wc -l | tr -d ' ')
  echo "CC↔CAI SYNC: $COUNT unread message(s) from CAI in inbox:"
  echo "$UNREAD" | while read -r MSG; do
    TYPE=$(echo "$MSG" | jq -r '.type')
    PRIORITY=$(echo "$MSG" | jq -r '.priority // "normal"')
    CONTENT=$(echo "$MSG" | jq -r '.content' | head -c 200)
    echo "  [$PRIORITY] ($TYPE) $CONTENT"
  done
  echo "To acknowledge, append an ack message to .claude/sync/inbox.jsonl"
fi

exit 0
