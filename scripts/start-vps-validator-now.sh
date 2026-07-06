#!/usr/bin/env bash
# Run ON validator VPS — resync existing node (keys preserved).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="${REPO_ROOT:-$ROOT_DIR}"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/validator-common.sh"

VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
BINARY="$(validator_ensure_sudod_binary "$ROOT_DIR" | tail -1)"

validator_load_network_defaults "$REPO_ROOT"

[[ -x "$BINARY" ]] || { echo "ERROR: sudod not found. Run: bash install-validator.sh"; exit 1; }

echo "=============================================="
echo "  SUDO validator — resync from seed"
echo "=============================================="

GENESIS="$VALIDATOR_HOME/config/genesis.json"
validator_fetch_live_genesis "$GENESIS" "$REPO_ROOT" || true
IH="$(python3 -c "import json; print(json.load(open('$GENESIS')).get('initial_height','?'))" 2>/dev/null || echo '?')"
echo "    genesis initial_height=$IH"

systemctl stop sudo-validator 2>/dev/null || true
validator_stop_node "$VALIDATOR_HOME"

PEER="${SEED_NODE_ID}@${SEED_IP}:${SEED_P2P_PORT}"
validator_configure_node \
  "$VALIDATOR_HOME/config/config.toml" \
  "$VALIDATOR_HOME/config/app.toml" \
  "$PEER" \
  "$(validator_detect_public_ip)"
validator_disable_statesync "$VALIDATOR_HOME/config/config.toml"
validator_reset_chain_data "$BINARY" "$VALIDATOR_HOME"

if [[ ! -f /etc/systemd/system/sudo-validator.service ]]; then
  validator_install_systemd "$BINARY" "$VALIDATOR_HOME"
else
  systemctl daemon-reload
  systemctl enable sudo-validator
  systemctl start sudo-validator
fi

sleep 8
systemctl status sudo-validator --no-pager 2>/dev/null | head -12 || true
curl -sf localhost:26657/status 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)['result']['sync_info']
print('height:', d['latest_block_height'], '| catching_up:', d['catching_up'])
" || echo "RPC starting — check: journalctl -u sudo-validator -f"

validator_unjail_if_needed "$BINARY" "$VALIDATOR_HOME" "${KEY_NAME:-validator}" || true
