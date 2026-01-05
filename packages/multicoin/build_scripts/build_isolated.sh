#!/usr/bin/env bash
set -euo pipefail

# Creates a throwaway Sui client config in a temp directory so the global
# ~/.sui state (and potentially corrupted keystore) are not touched.

if ! command -v sui >/dev/null 2>&1; then
  echo "sui CLI not found in PATH" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sui_build_XXXXXX")
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT

CLIENT_CFG="$TMP_DIR/client.yaml"
KEYSTORE="$TMP_DIR/keystore"

# Minimal valid JSON keystore (empty array)
echo '[]' > "$KEYSTORE"

cat > "$CLIENT_CFG" <<EOF
---
keystore:
  File: $KEYSTORE
envs:
  - alias: localnet
    rpc: http://127.0.0.1:9000
active_env: localnet
active_address: null
EOF

echo "Using isolated SUI_CLIENT_CONFIG at $CLIENT_CFG" >&2
SUI_CLIENT_CONFIG="$CLIENT_CFG" sui move build --dump-bytecode-as-base64 --ignore-chain > build_artifacts.json
echo "Build complete (isolated). Artifacts in build_artifacts.json"
