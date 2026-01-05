#!/usr/bin/env bash
set -euo pipefail

#!/usr/bin/env bash
## Automatically publishes the package when build_artifacts.json changes.
## Designed to be triggered by a file watcher (watchexec on build_artifacts.json).
## Avoids redundant publishes by hashing the artifact file.

ARTIFACT=build_artifacts.json
STATE_FILE=.last_publish_hash

if [ ! -f "$ARTIFACT" ]; then
  echo "[deploy-watch] No build artifacts yet (waiting for initial build)." >&2
  exit 0
fi

if ! command -v shasum >/dev/null 2>&1; then
  echo "[deploy-watch] shasum not found (macOS should have it); skipping." >&2
  exit 0
fi

HASH=$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')
if [ -f "$STATE_FILE" ] && grep -q "$HASH" "$STATE_FILE"; then
  echo "[deploy-watch] No changes in build artifacts (hash unchanged). Skipping publish." >&2
  exit 0
fi

echo "[deploy-watch] Detected new build artifacts (hash $HASH). Preparing to publish..." >&2

# Ensure we have at least one managed address. If none, create and faucet fund it.
ensure_address() {
  local existing
  existing=$(sui client addresses 2>/dev/null | awk '/0x[0-9a-fA-F]{64}/ {print $1}') || true
  if [ -n "$existing" ]; then
    # Make sure an active address is set
    local active
    active=$(sui client active-address 2>/dev/null || true)
    ADDRESS=$(sui client active-address)

    echo "[deploy-watch] Detected existing managed addresses. $ADDRESS"
    if [ -z "$active" ]; then
      # Pick the first existing one
      echo "[deploy-watch] Setting active address to $ADDRESS" >&2
      sui client switch --address "$ADDRESS" >/dev/null
    fi
    return 0
  fi

  echo "[deploy-watch] No managed addresses detected. Creating one..." >&2
  if ! sui client new-address ed25519 >/dev/null; then
    echo "[deploy-watch] Failed to create new address." >&2
    return 1
  fi
  local newaddr
  newaddr=$(sui client active-address 2>/dev/null || true)
  echo "[deploy-watch] Created address $newaddr. Requesting faucet (if available)..." >&2
  # Faucet may fail if local faucet not ready; ignore errors.
  sui client faucet --address "$newaddr" >/dev/null 2>&1 || true
}

if ! ensure_address; then
  echo "[deploy-watch] Cannot proceed without an address. Skipping publish." >&2
  exit 1
fi

REQUIRED_GAS_BUDGET=${REQUIRED_GAS_BUDGET:-30000000}
MIN_BALANCE=$(( REQUIRED_GAS_BUDGET * 2 )) # keep a buffer (2x gas budget)
MAX_FAUCET_ATTEMPTS=${MAX_FAUCET_ATTEMPTS:-8}
SLEEP_BETWEEN_FAUCET=${SLEEP_BETWEEN_FAUCET:-2}

# ls
PACKAGE_PATH=${PACKAGE_PATH:-.}
ls "$PACKAGE_PATH"/
if [ ! -f "$PACKAGE_PATH/Move.toml" ]; then
  echo "[deploy-watch] ERROR: Expected Move.toml at $PACKAGE_PATH but not found." >&2
  exit 1
fi

echo "[deploy-watch] Publishing package at $PACKAGE_PATH to local network (gas budget $REQUIRED_GAS_BUDGET)..." >&2
if ! bash build_scripts/publish_local.sh "$PACKAGE_PATH"; then
  echo "[deploy-watch] Publish failed (will retry on next artifact change)." >&2
  exit 1
fi

echo "$HASH" > "$STATE_FILE"
echo "[deploy-watch] Publish complete. Stored hash in $STATE_FILE" >&2
