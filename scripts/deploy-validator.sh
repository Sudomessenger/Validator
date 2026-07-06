#!/usr/bin/env bash
# Deploy a new SUDO validator on a fresh server.
#
# Usage:
#   export SEED_IP="1.2.3.4"          # required: primary node public IP
#   export MONIKER="my-validator"     # optional
#   export STAKE_SUDO=1000            # optional: self-delegation
#   export VALIDATOR_HOME=/opt/sudo-validator
#   ./scripts/deploy-validator.sh setup
#   ./scripts/deploy-validator.sh start
#   ./scripts/deploy-validator.sh status
#   ./scripts/deploy-validator.sh register   # after wallet funded + synced
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/validator-common.sh"
validator_load_network_defaults "$ROOT_DIR"
BINARY="$(validator_ensure_sudod_binary "$ROOT_DIR")"
CHAIN_ID="${CHAIN_ID:-sudo99}"
VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
MONIKER="${MONIKER:-sudo-validator}"
STAKE_SUDO="${STAKE_SUDO:-1000}"
KEYRING_BACKEND="${KEYRING_BACKEND:-file}"
SEED_NODE_ID="${SEED_NODE_ID:-6eafed75e8db7b0eed2f608b211afde9f71de184}"
SEED_P2P_PORT="${SEED_P2P_PORT:-26656}"
RPC_PORT="${RPC_PORT:-26657}"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

require_seed_ip() {
  [[ -n "${SEED_IP:-}" ]] || die "Set SEED_IP to the primary node's public IP (export SEED_IP=...)"
}

stake_bash() {
  python3 -c "print(int(${STAKE_SUDO}) * 10**9)"
}

cmd_setup() {
  require_seed_ip

  info "Installing build deps (apt)..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq build-essential git jq curl python3 >/dev/null 2>&1 || true
  fi

  if [[ ! -x "$BINARY" ]]; then
    die "sudod not found — run join-validator.sh or scripts/download-sudod.sh"
  fi

  info "Initializing node (home=$VALIDATOR_HOME, moniker=$MONIKER)..."
  mkdir -p "$VALIDATOR_HOME"
  if [[ ! -f "$VALIDATOR_HOME/config/genesis.json" ]]; then
    "$BINARY" init "$MONIKER" --chain-id "$CHAIN_ID" --home "$VALIDATOR_HOME"
  else
    info "Genesis already exists, skipping init"
  fi

  GENESIS_SRC="${GENESIS_SRC:-}"
  if [[ -n "$GENESIS_SRC" && -f "$GENESIS_SRC" ]]; then
    info "Copying genesis from GENESIS_SRC=$GENESIS_SRC"
    cp "$GENESIS_SRC" "$VALIDATOR_HOME/config/genesis.json"
  elif [[ -z "$(jq -r '.chain_id // empty' "$VALIDATOR_HOME/config/genesis.json" 2>/dev/null)" ]]; then
    info "Fetching genesis from seed node..."
    scp -o StrictHostKeyChecking=accept-new "root@${SEED_IP}:/tmp/sudo-localnet/config/genesis.json" \
      "$VALIDATOR_HOME/config/genesis.json" || \
      die "Could not fetch genesis. Set GENESIS_SRC=/path/to/genesis.json or copy manually."
  fi

  "$BINARY" genesis validate-genesis --home "$VALIDATOR_HOME"

  PEER="${SEED_NODE_ID}@${SEED_IP}:${SEED_P2P_PORT}"
  info "Configuring peers: $PEER"

  CONFIG="$VALIDATOR_HOME/config/config.toml"
  APP="$VALIDATOR_HOME/config/app.toml"

  sed -i 's/^timeout_commit = .*/timeout_commit = "3600ms"/' "$CONFIG"
  sed -i 's/^laddr = "tcp:\/\/127.0.0.1:26657"/laddr = "tcp:\/\/0.0.0.0:26657"/' "$CONFIG"
  sed -i 's/^persistent_peers = .*/persistent_peers = "'"$PEER"'"/' "$CONFIG"

  if [[ -n "${EXTERNAL_IP:-}" ]]; then
    sed -i 's/^external_address = .*/external_address = "'"$EXTERNAL_IP"':26656"/' "$CONFIG"
  fi

  sed -i 's/^minimum-gas-prices = .*/minimum-gas-prices = "0.001bash"/' "$APP"

  if ! "$BINARY" keys show validator --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND" &>/dev/null; then
    info "Creating validator wallet key (save mnemonic!)..."
    "$BINARY" keys add validator --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND"
  fi

  WALLET="$("$BINARY" keys show validator -a --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND")"
  NODE_ID="$("$BINARY" tendermint show-node-id --home "$VALIDATOR_HOME")"
  CONSENSUS="$("$BINARY" tendermint show-validator --home "$VALIDATOR_HOME")"

  cat >"$VALIDATOR_HOME/deploy-info.txt" <<EOF
SUDO Validator deploy info
==========================
Chain ID:     $CHAIN_ID
Home:         $VALIDATOR_HOME
Moniker:      $MONIKER
Node ID:      $NODE_ID
Wallet:       $WALLET
Stake:        ${STAKE_SUDO} SUDO ($(stake_bash) bash)
Seed peer:    $PEER
Consensus:    $CONSENSUS

Next steps:
  1. Open firewall port 26656 on THIS server
  2. Ensure seed node allows inbound 26656 from this IP
  3. Fund wallet $WALLET with >= ${STAKE_SUDO} SUDO + fees
  4. ./scripts/deploy-validator.sh start
  5. ./scripts/deploy-validator.sh status   (wait for catching_up=false)
  6. ./scripts/deploy-validator.sh register
EOF

  info "Setup complete. See $VALIDATOR_HOME/deploy-info.txt"
  cat "$VALIDATOR_HOME/deploy-info.txt"
}

cmd_start() {
  [[ -x "$BINARY" ]] || die "Binary not found: $BINARY (run setup first)"
  info "Starting validator node..."
  exec "$BINARY" start --home "$VALIDATOR_HOME"
}

cmd_start_bg() {
  [[ -x "$BINARY" ]] || die "Binary not found: $BINARY"
  info "Starting validator node in background..."
  nohup "$BINARY" start --home "$VALIDATOR_HOME" >"$VALIDATOR_HOME/node.log" 2>&1 &
  echo $! >"$VALIDATOR_HOME/node.pid"
  info "PID $(cat "$VALIDATOR_HOME/node.pid"), log: $VALIDATOR_HOME/node.log"
}

cmd_status() {
  curl -sf "http://127.0.0.1:${RPC_PORT}/status" | jq '{
    chain_id: .result.node_info.network,
    height: .result.sync_info.latest_block_height,
    catching_up: .result.sync_info.catching_up,
    time: .result.sync_info.latest_block_time
  }' || die "Node not reachable on port $RPC_PORT"
}

cmd_register() {
  [[ -x "$BINARY" ]] || die "Binary not found: $BINARY"
  STAKE="$(stake_bash)"
  PUBKEY="$("$BINARY" tendermint show-validator --home "$VALIDATOR_HOME")"

  VALIDATOR_JSON="$VALIDATOR_HOME/validator.json"
  cat >"$VALIDATOR_JSON" <<EOF
{
  "pubkey": $PUBKEY,
  "amount": "${STAKE}bash",
  "moniker": "$MONIKER",
  "identity": "",
  "website": "",
  "security": "",
  "details": "SUDO validator",
  "commission-rate": "0.10",
  "commission-max-rate": "0.20",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "${STAKE}"
}
EOF

  info "Submitting create-validator (${STAKE_SUDO} SUDO)..."
  "$BINARY" tx staking create-validator "$VALIDATOR_JSON" \
    --from validator \
    --chain-id "$CHAIN_ID" \
    --home "$VALIDATOR_HOME" \
    --keyring-backend "$KEYRING_BACKEND" \
    --gas 300000 \
    --fees 500bash \
    -y

  info "Validator registered. Valoper:"
  "$BINARY" keys show validator --bech val -a --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND"
}

cmd_help() {
  cat <<EOF
Usage: $0 <command>

Commands:
  setup       Build binary, init node, fetch genesis, configure peers
  start       Start node (foreground)
  start-bg    Start node in background
  status      Show sync status
  register    Submit create-validator tx (wallet must be funded)
  help        Show this help

Environment:
  SEED_IP          Primary node public IP (required for setup)
  MONIKER          Validator name (default: sudo-validator)
  STAKE_SUDO       Self-delegation (default: 1000)
  VALIDATOR_HOME   Node home (default: /opt/sudo-validator)
  GENESIS_SRC      Local path to genesis.json (optional)
  EXTERNAL_IP      This server's public IP for P2P (optional)
EOF
}

main() {
  case "${1:-help}" in
    setup) cmd_setup ;;
    start) cmd_start ;;
    start-bg) cmd_start_bg ;;
    status) cmd_status ;;
    register) cmd_register ;;
    help|--help|-h) cmd_help ;;
    *) die "Unknown command: $1 (try: $0 help)" ;;
  esac
}

main "$@"
