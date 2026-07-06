#!/usr/bin/env bash
# Run ON validator VPS after sync complete.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/validator-common.sh"

VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
BINARY="$(validator_ensure_sudod_binary "$ROOT_DIR" | tail -1)"
KEY_NAME="${KEY_NAME:-validator}"

[[ -x "$BINARY" ]] || { echo "ERROR: sudod not found"; exit 1; }

validator_load_network_defaults "$ROOT_DIR"
validator_unjail_if_needed "$BINARY" "$VALIDATOR_HOME" "$KEY_NAME"
