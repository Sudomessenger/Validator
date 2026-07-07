#!/usr/bin/env bash
# JSON status for app backend polling (node vs bonded).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/validator-common.sh"

VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
validator_load_network_defaults "$ROOT_DIR"

BINARY="/usr/local/bin/sudod"
[[ -x "$BINARY" ]] || BINARY="$(validator_ensure_sudod_binary "$ROOT_DIR" 2>/dev/null | tail -1 || true)"

node_running="false"
synced="false"
height="0"
catching_up="true"
wallet=""
valoper=""
bonded="false"
balance_bash="0"
systemd_active="false"

if systemctl is-active sudo-validator &>/dev/null; then
  systemd_active="true"
  node_running="true"
fi

if curl -sf --max-time 5 http://127.0.0.1:26657/status >/tmp/vstat.json 2>/dev/null; then
  node_running="true"
  height="$(jq -r '.result.sync_info.latest_block_height' /tmp/vstat.json)"
  catching_up="$(jq -r '.result.sync_info.catching_up' /tmp/vstat.json)"
  [[ "$catching_up" == "false" && "$height" != "0" ]] && synced="true"
fi

if [[ -n "$BINARY" && -x "$BINARY" ]]; then
  validator_setup_lib_path "$ROOT_DIR"
  wallet="$("$BINARY" keys show validator -a --home "$VALIDATOR_HOME" --keyring-backend test 2>/dev/null || true)"
  valoper="$("$BINARY" keys show validator --bech val -a --home "$VALIDATOR_HOME" --keyring-backend test 2>/dev/null || true)"
  if [[ -n "$wallet" ]]; then
    balance_bash="$(validator_get_balance_bash "$BINARY" "$wallet" 2>/dev/null || echo 0)"
  fi
  if [[ -n "$valoper" ]] && validator_is_bonded_on_chain "$BINARY" "$VALIDATOR_HOME"; then
    bonded="true"
  fi
fi

if [[ "$bonded" == "true" ]]; then
  deploy_status="validator_bonded"
elif [[ "$node_running" == "true" && "$synced" == "true" ]]; then
  deploy_status="node_running_not_bonded"
elif [[ "$node_running" == "true" ]]; then
  deploy_status="node_syncing"
else
  deploy_status="node_stopped"
fi

python3 - <<PY
import json
print(json.dumps({
  "deploy_status": "$deploy_status",
  "node_running": $([ "$node_running" = true ] && echo True || echo False),
  "systemd_active": $([ "$systemd_active" = true ] && echo True || echo False),
  "synced": $([ "$synced" = true ] && echo True || echo False),
  "height": "$height",
  "catching_up": $([ "$catching_up" = true ] && echo True || echo False),
  "bonded": $([ "$bonded" = true ] && echo True || echo False),
  "wallet": "$wallet",
  "valoper": "$valoper",
  "balance_bash": "$balance_bash",
  "explorer": "https://sudoscan.io/validators",
}, indent=2))
PY
