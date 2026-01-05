#!/usr/bin/env bash
set -euo pipefail

# if [ -n "${ISOLATED:-}" ]; then
# 	echo "ISOLATED build requested -> delegating to scripts/build_isolated.sh" >&2
# 	bash "$(dirname "$0")/build_isolated.sh"
# 	exit 0
# fi
echo "Starting standard build (non-isolated)..."
if [ -f .env ]; then set -a; source .env; set +a; fi
echo "Sourcing .env (if any) done."

bash "$(dirname "$0")/fix_client_config.sh" || true
echo "Client config fixup (if any) done."
echo "Building Move package (global config, --ignore-chain)..."
if ! sui move build --dump-bytecode-as-base64 --ignore-chain > build_artifacts.json 2> build_err.log; then
	echo "Build failed. See build_err.log" >&2
	exit 1
fi

# Ensure output file is valid JSON by a minimal check (jq optional)
if command -v jq >/dev/null 2>&1; then
	if ! jq empty build_artifacts.json >/dev/null 2>&1; then
		echo "Warning: build_artifacts.json not valid JSON (Move CLI may have printed prompts)." >&2
		echo "Tip: Ensure localnet is running or client config is correct." >&2
	fi
fi

echo "Build complete. Artifacts written to build_artifacts.json"
