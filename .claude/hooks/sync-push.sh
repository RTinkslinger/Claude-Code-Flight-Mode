#!/bin/bash
# Cross-Sync: Stop hook — update state.json, append inbox status, push
# Type: command | Event: Stop
#
# Fires as the LAST Stop group (after CBS and sync prompt hooks) so that
# semantic state.json updates from prompt hooks are included in the push.
#
# Idempotency: Uses a push marker (.claude/sync/.last-push) to prevent
# duplicate inbox messages when Stop fires multiple times (e.g., after
# stop-check.sh exit 2 triggers a continue-then-retry cycle).
#
# Exit codes: Always 0 — sync failure never blocks session end.
# Dependencies: jq (required), git (required)

# jq is required for state.json updates and inbox message construction
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0
cd "$CWD" 2>/dev/null || exit 0

# Only run if sync is initialized
[ -d ".claude/sync" ] || exit 0
[ -f ".claude/sync/state.json" ] || exit 0
[ -f ".claude/sync/inbox.jsonl" ] || exit 0

STATE=".claude/sync/state.json"
INBOX=".claude/sync/inbox.jsonl"
PUSH_MARKER=".claude/sync/.last-push"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
LAST_COMMIT_MSG=$(git log -1 --format='%s' 2>/dev/null || echo "")

# Changed files (excluding sync files themselves — fixed string match, not regex)
CHANGED_FILES=$(git status --porcelain 2>/dev/null \
  | grep -vF '.claude/sync/' \
  | awk '{print $NF}' \
  | head -10 \
  | jq -R -s 'split("\n") | map(select(. != ""))' 2>/dev/null || echo '[]')

# --- Update state.json: mechanical fields only ---
# Preserves all semantic fields (current_tasks, recent_decisions, etc.)
# that Claude may have updated via the prompt-type Stop hook.
jq --arg ts "$TIMESTAMP" \
   --argjson files "$CHANGED_FILES" \
   '.state.last_session.timestamp = $ts |
    .state.key_files_changed_last_session = $files |
    .updated_at = $ts |
    .updated_by = "cc"' "$STATE" > "${STATE}.tmp" 2>/dev/null \
  && mv "${STATE}.tmp" "$STATE"

# --- Append inbox status message (with dedup) ---
# Skip if we already pushed within the last 2 minutes (handles repeated Stop events)
SKIP_INBOX=false
if [ -f "$PUSH_MARKER" ]; then
  LAST_PUSH=$(cat "$PUSH_MARKER" 2>/dev/null || echo "0")
  NOW=$(date +%s)
  if [ $((NOW - LAST_PUSH)) -lt 120 ]; then
    SKIP_INBOX=true
  fi
fi

if [ "$SKIP_INBOX" = "false" ]; then
  # Build status content from available context
  CONTENT="Session closed. Branch: $BRANCH."
  [ -n "$LAST_COMMIT_MSG" ] && CONTENT="$CONTENT Last commit: $LAST_COMMIT_MSG."

  MSG_ID="msg_$(date +%Y%m%d_%H%M%S)_cc_status"
  STATUS_MSG=$(jq -c -n \
    --arg id "$MSG_ID" \
    --arg ts "$TIMESTAMP" \
    --arg content "$CONTENT" \
    --arg branch "$BRANCH" \
    --argjson files "$CHANGED_FILES" \
    '{
      id: $id,
      timestamp: $ts,
      source: "cc",
      type: "status",
      priority: "normal",
      content: $content,
      context: { branch: $branch, files_changed: $files },
      ack: null
    }')

  echo "$STATUS_MSG" >> "$INBOX"
  date +%s > "$PUSH_MARKER"
fi

# --- Pull (rebase) then commit and push ---
# Rebase handles append-only JSONL conflicts from concurrent writes gracefully
git pull --rebase --quiet 2>/dev/null

# Only add specific sync files (not .last-push marker)
git add .claude/sync/state.json .claude/sync/inbox.jsonl 2>/dev/null

# Skip if nothing to commit
git diff --cached --quiet 2>/dev/null && exit 0

git commit -m "sync: session state update" --quiet 2>/dev/null
git push --quiet 2>/dev/null

# Always exit 0 — sync failure should never block session end
exit 0
