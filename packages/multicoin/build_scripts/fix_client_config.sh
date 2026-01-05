#!/usr/bin/env bash
set -euo pipefail

CFG_DIR="$HOME/.sui/sui_config"
CLIENT_CFG="$CFG_DIR/client.yaml"
KEYSTORE="$CFG_DIR/keystore"

mkdir -p "$CFG_DIR"
touch "$KEYSTORE"

if [ -f "$CLIENT_CFG" ]; then
  # If it already has 'rpc:' assume it's fine.
  if grep -qE '^\s*rpc:' "$CLIENT_CFG"; then
    exit 0
  fi
  # If it has legacy 'url:' replace with 'rpc:' inline preserving indentation.
  if grep -q 'url:' "$CLIENT_CFG"; then
    sed -i.bak 's/url:/rpc:/g' "$CLIENT_CFG"
    echo "Patched legacy 'url:' to 'rpc:' in $CLIENT_CFG (backup at $CLIENT_CFG.bak)" >&2
    exit 0
  fi
  # Otherwise leave existing file (avoid overwriting unknown schema)
  exit 0
fi

echo "Generating minimal Sui client config (no addresses) at $CLIENT_CFG" >&2
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

echo "Created $CLIENT_CFG"