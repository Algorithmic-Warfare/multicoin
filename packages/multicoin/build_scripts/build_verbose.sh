#!/usr/bin/env bash
set -euo pipefail

if [ -f .env ]; then set -a; source .env; set +a; fi

echo "Verbose Sui Move build (capturing stderr/stdout)..."
sui move build --dump-bytecode-as-base64 2>&1 | tee build_verbose.log
