#!/bin/bash
# Cross-Sync: SessionStart hook — pull latest sync state, check inbox
# Type: command | Event: SessionStart | Matcher: startup
#
# Fires alongside Cash Build System startup hook. Pulls latest .claude/sync/
# from remote, checks inbox.jsonl for unacknowledged external messages
# (CAI + cross-project CC), and outputs a summary for Claude to act on.
#
# Exit codes: Always 0 (informational only, never blocks session start)
# Output: stdout → fed to Claude as session context
# Dependencies: jq (required), git (optional — degrades gracefully)

# jq is required for inbox parsing
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0
cd "$CWD" 2>/dev/null || exit 0

# Only run if sync is initialized
[ -d ".claude/sync" ] || exit 0

# Clear push marker from previous session (allows fresh push this session)
rm -f ".claude/sync/.last-push"

# Pull latest changes (quiet, non-fatal — works offline gracefully)
# ff-only avoids rebase failures on dirty working trees; if diverged, next session reconciles
git pull --ff-only --quiet 2>/dev/null

# Check inbox for unread external messages
INBOX=".claude/sync/inbox.jsonl"
[ -f "$INBOX" ] || exit 0

# Collect all acknowledged message IDs (per-line processing for malformed JSONL resilience)
ACKED=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  # Normalize: handle both array and string references
  IDS=$(echo "$line" | jq -r 'select(.type == "ack") | (.context.references // []) | if type == "array" then .[] else . end' 2>/dev/null)
  [ -n "$IDS" ] && ACKED="$ACKED
$IDS"
done < "$INBOX"
ACKED=$(echo "$ACKED" | sort -u)

# Find unacknowledged external messages (per-line processing for malformed JSONL resilience)
UNREAD_COUNT=0
UNREAD_DETAIL=""

while IFS= read -r line; do
  [ -z "$line" ] && continue
  MSG_ID=$(echo "$line" | jq -r 'select((.source == "cai" or (.source | startswith("cc:"))) and .type != "ack") | .id' 2>/dev/null)
  [ -z "$MSG_ID" ] && continue
  # Check if already acknowledged
  if ! echo "$ACKED" | grep -qxF "$MSG_ID"; then
    UNREAD_COUNT=$((UNREAD_COUNT + 1))
    DETAIL=$(echo "$line" | jq -r '"  [\(.priority // "normal")] \(.type): \(.content[0:150])"' 2>/dev/null)
    UNREAD_DETAIL="$UNREAD_DETAIL
$DETAIL"
  fi
done < "$INBOX"

[ "$UNREAD_COUNT" -eq 0 ] && exit 0

# Output unread messages as session context
echo "CROSS-SYNC: $UNREAD_COUNT unread message(s) from external sources:"
echo "$UNREAD_DETAIL"
echo ""
echo "Review and acknowledge these messages. To ack, append a message with type:ack and context.references:[\"msg_id\"] to .claude/sync/inbox.jsonl."

exit 0
