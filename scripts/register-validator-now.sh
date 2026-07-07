#!/usr/bin/env bash
# Submit create-validator if node is synced but validator not bonded on-chain.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/validator-common.sh"

VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
MONIKER="${MONIKER:-sudo-validator}"
KEYRING_BACKEND="${KEYRING_BACKEND:-test}"

validator_load_network_defaults "$ROOT_DIR"
BINARY="$(validator_ensure_sudod_binary "$ROOT_DIR" | tail -1)"
validator_setup_lib_path "$ROOT_DIR"

echo "==> Checking validator bond status..."
if validator_is_registered "$BINARY" "$VALIDATOR_HOME"; then
  echo "OK: Validator already bonded on-chain"
  validator_print_final_status "$BINARY" "$VALIDATOR_HOME" "bonded"
  exit 0
fi

if ! curl -sf http://127.0.0.1:26657/status | jq -e '.result.sync_info.catching_up == false' >/dev/null; then
  echo "ERROR: Node not synced yet — wait for catching_up=false" >&2
  exit 1
fi

if ! "$BINARY" keys show validator --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND" &>/dev/null; then
  echo "ERROR: Wallet key 'validator' missing. Re-import private key:" >&2
  echo "  export VALIDATOR_PRIVATE_KEY=0x... && bash $ROOT_DIR/scripts/join-validator.sh --no-wait" >&2
  exit 1
fi

WALLET="$("$BINARY" keys show validator -a --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND")"
BAL="$(validator_get_balance_bash "$BINARY" "$WALLET" || echo 0)"
MIN="$(validator_min_balance_bash)"
if ! python3 -c "exit(0 if int('${BAL:-0}') >= int('${MIN}') else 1)"; then
  echo "ERROR: Insufficient balance on $WALLET (need >= 1001 SUDO)" >&2
  exit 1
fi

echo "==> Submitting create-validator (${STAKE_SUDO} SUDO)..."
validator_register "$BINARY" "$VALIDATOR_HOME" "$MONIKER"
sleep 10

if validator_is_registered "$BINARY" "$VALIDATOR_HOME"; then
  echo "OK: Validator bonded"
  validator_print_final_status "$BINARY" "$VALIDATOR_HOME" "bonded"
else
  echo "ERROR: create-validator submitted but still not bonded — check tx in logs" >&2
  validator_print_final_status "$BINARY" "$VALIDATOR_HOME" "not_bonded"
  exit 1
fi
