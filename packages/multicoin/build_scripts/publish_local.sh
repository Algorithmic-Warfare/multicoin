#!/usr/bin/env bash
set -euo pipefail

INITIAL_SUPPLY=${INITIAL_SUPPLY:-1000000}
NAME=${NAME:-MyToken}
SYMBOL=${SYMBOL:-MTK}
DECIMALS=${DECIMALS:-9}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

PACKAGE_PATH=${1:-packages/contracts}

if [ ! -f "./Move.toml" ]; then
  echo "Expected Move.toml in $PACKAGE_PATH, but not found." >&2
  exit 1
fi

echo "Publishing package ($PACKAGE_PATH) to local network (capturing JSON output)..."

# Prefer JSON output for reliable parsing. Capture ONLY stdout (pure JSON) then echo it for visibility.
if ! PUBLISH_JSON=$(sui client publish --gas-budget 30000000 --skip-dependency-verification --json ); then
  echo "Publish command failed (non-zero exit)." >&2
  exit 1
fi
echo "$PUBLISH_JSON" >&2

# Persist raw output for debugging (rotated to keep only last 5 copies)
LOG_FILE=.last_publish_output.json
if [ -f "$LOG_FILE" ]; then
  mv "$LOG_FILE" "$LOG_FILE.$(date +%s)" 2>/dev/null || true
  ls -t .last_publish_output.json.* 2>/dev/null | tail -n +6 | xargs -r rm -- 2>/dev/null || true
fi
echo "$PUBLISH_JSON" > "$LOG_FILE"

# Try multiple strategies to extract the package id.
PACKAGE_ID=$(echo "$PUBLISH_JSON" | jq -r '.packageId // empty')
if [ -z "$PACKAGE_ID" ] || [ "$PACKAGE_ID" = "null" ]; then
  # Fallback: look into created objects for an immutable object id (older/newer CLI variants)
  PACKAGE_ID=$(echo "$PUBLISH_JSON" | jq -r '.effects.created[]? | select(.owner=="Immutable").reference.objectId' | head -n1)
fi
if [ -z "$PACKAGE_ID" ] || [ "$PACKAGE_ID" = "null" ]; then
  # Final grep fallback (case-insensitive) if JSON parse failed for some reason (e.g., non-json sections interleaved)
  PACKAGE_ID=$(echo "$PUBLISH_JSON" | grep -Eio 'package[id[:space:]]+0x[0-9a-f]{64}' | grep -Eio '0x[0-9a-f]{64}' | head -n1 || true)
fi

if [ -z "$PACKAGE_ID" ]; then
  echo "Failed to parse package id from publish output. See $LOG_FILE for raw output." >&2
  # Do NOT silently succeed; this should remain a hard failure so callers can react.
  exit 1
fi

cat > .env.local <<EOF
PACKAGE_ID=$PACKAGE_ID
NAME=$NAME
SYMBOL=$SYMBOL
DECIMALS=$DECIMALS
INITIAL_SUPPLY=$INITIAL_SUPPLY
EOF

echo "Stored deployment info in .env.local"
echo "PACKAGE_ID=$PACKAGE_ID"
