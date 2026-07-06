#!/usr/bin/env bash
# Download pre-built sudod binary — no Sudomessenger/network repo required.
#
# Usage:
#   bash scripts/download-sudod.sh
#   SUDOD_DOWNLOAD_URL=https://... bash scripts/download-sudod.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/validator-common.sh"

validator_load_network_defaults "$ROOT"
DEST="${SUDOD_BIN:-$ROOT/build/sudod}"
validator_download_sudod "$ROOT" "$DEST"
echo "OK: $DEST"
