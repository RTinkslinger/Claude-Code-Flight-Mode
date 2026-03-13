#!/bin/bash
# Cross-Sync: Validated inbox write helper
# Usage: echo '{"id":"...","source":"...","type":"...","content":"..."}' | sync-write.sh /path/to/inbox.jsonl
#
# Validates JSON structure and required fields before appending to inbox.
# Ensures the written line is compact (single-line) JSONL.
# Prevents malformed writes from corrupting the inbox.
#
# Exit codes: 0 = success, 1 = validation error (message on stderr)
# Dependencies: jq (required)

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required for sync-write.sh" >&2; exit 1; }

INBOX="$1"
if [ -z "$INBOX" ]; then
  echo "ERROR: Usage: echo '{...}' | sync-write.sh /path/to/inbox.jsonl" >&2
  exit 1
fi

# Read message from stdin
MSG=$(cat)
if [ -z "$MSG" ]; then
  echo "ERROR: Empty message" >&2
  exit 1
fi

# Validate JSON syntax
if ! echo "$MSG" | jq '.' >/dev/null 2>&1; then
  echo "ERROR: Invalid JSON — message not written to inbox" >&2
  exit 1
fi

# Validate required fields exist and are non-empty strings
VALIDATION=$(echo "$MSG" | jq -r '
  if (.id | type) != "string" or (.id | length) == 0 then "missing or empty: id"
  elif (.source | type) != "string" or (.source | length) == 0 then "missing or empty: source"
  elif (.type | type) != "string" or (.type | length) == 0 then "missing or empty: type"
  elif (.content | type) != "string" or (.content | length) == 0 then "missing or empty: content"
  else "ok"
  end' 2>/dev/null)

if [ "$VALIDATION" != "ok" ]; then
  echo "ERROR: $VALIDATION — message not written to inbox" >&2
  exit 1
fi

# Validate type is a known message type
MSG_TYPE=$(echo "$MSG" | jq -r '.type' 2>/dev/null)
case "$MSG_TYPE" in
  decision|question|answer|task|status|note|research|flag|ack) ;;
  *) echo "ERROR: unknown message type '$MSG_TYPE' — expected one of: decision, question, answer, task, status, note, research, flag, ack" >&2; exit 1 ;;
esac

# For ack messages, validate context.references exists and is an array
if [ "$MSG_TYPE" = "ack" ]; then
  REF_TYPE=$(echo "$MSG" | jq -r '.context.references | type' 2>/dev/null)
  if [ "$REF_TYPE" != "array" ]; then
    echo "ERROR: ack messages require context.references as an array" >&2
    exit 1
  fi
fi

# Ensure parent directory exists
INBOX_DIR=$(dirname "$INBOX")
if [ ! -d "$INBOX_DIR" ]; then
  echo "ERROR: inbox directory does not exist: $INBOX_DIR" >&2
  exit 1
fi

# Append as compact single-line JSONL
echo "$MSG" | jq -c '.' >> "$INBOX"
exit 0
