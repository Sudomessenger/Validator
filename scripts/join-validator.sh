#!/usr/bin/env bash
# One-command SUDO validator join.
#
# Any user: git clone → run this script → fund wallet → validator auto-activates.
#
# Quick start (new wallet — script generates address for you):
#   git clone https://github.com/Sudomessenger/Validator.git
#   cd Validator
#   ./join-validator.sh
#
# Existing wallet — use ONE of these:
#   ./scripts/join-validator.sh --mnemonic "word1 word2 ... word24"
#   ./scripts/join-validator.sh --private-key "HEX_PRIVATE_KEY"
#   echo "mnemonic..." | ./scripts/join-validator.sh --mnemonic-stdin
#   echo "hexkey..."   | ./scripts/join-validator.sh --private-key-stdin
#
# Optional:
#   --address 99xxx...     Verify recovered wallet matches
#   --moniker my-name      Validator display name
#   --stake 1000           Required SUDO balance (default 1000)
#   --seed-ip 1.2.3.4      Primary node IP (default in config/validator-network.env)
#   --no-systemd           Skip systemd install
#   --no-wait              Don't wait for balance (fail if insufficient)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/validator-common.sh"

CHAIN_ROOT=""
BINARY=""
VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
KEYRING_BACKEND="${KEYRING_BACKEND:-file}"
MONIKER="${MONIKER:-sudo-validator}"
RPC_PORT="${RPC_PORT:-26657}"
INSTALL_SYSTEMD="${INSTALL_SYSTEMD:-1}"
WAIT_FOR_FUNDS="${WAIT_FOR_FUNDS:-1}"

WALLET_ADDRESS=""
WALLET_MNEMONIC=""
WALLET_PRIVATE_KEY=""
MNEMONIC_STDIN=0
PRIVATE_KEY_STDIN=0

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --address) WALLET_ADDRESS="$2"; shift 2 ;;
      --mnemonic) WALLET_MNEMONIC="$2"; shift 2 ;;
      --mnemonic-stdin) MNEMONIC_STDIN=1; shift ;;
      --private-key) WALLET_PRIVATE_KEY="$2"; shift 2 ;;
      --private-key-stdin) PRIVATE_KEY_STDIN=1; shift ;;
      --moniker) MONIKER="$2"; shift 2 ;;
      --stake) STAKE_SUDO="$2"; shift 2 ;;
      --seed-ip) SEED_IP="$2"; shift 2 ;;
      --no-systemd) INSTALL_SYSTEMD=0; shift ;;
      --no-wait) WAIT_FOR_FUNDS=0; shift ;;
      -h|--help) usage ;;
      *) die "Unknown option: $1 (try --help)" ;;
    esac
  done
}

ensure_wallet_key() {
  if [[ "$MNEMONIC_STDIN" == "1" ]]; then
    echo "==> Reading mnemonic from stdin..."
    read -r WALLET_MNEMONIC
  fi
  if [[ "$PRIVATE_KEY_STDIN" == "1" ]]; then
    echo "==> Reading private key from stdin..."
    read -r WALLET_PRIVATE_KEY
  fi

  # install-validator.sh / bootstrap pass credentials via env
  if [[ -z "$WALLET_PRIVATE_KEY" && -z "$WALLET_MNEMONIC" ]]; then
    if [[ -n "${VALIDATOR_PRIVATE_KEY:-}" ]]; then
      if validator_credential_looks_like_mnemonic "$VALIDATOR_PRIVATE_KEY"; then
        WALLET_MNEMONIC="${VALIDATOR_MNEMONIC:-$VALIDATOR_PRIVATE_KEY}"
      else
        WALLET_PRIVATE_KEY="$VALIDATOR_PRIVATE_KEY"
      fi
    elif [[ -n "${VALIDATOR_MNEMONIC:-}" ]]; then
      WALLET_MNEMONIC="$VALIDATOR_MNEMONIC"
    fi
  fi

  validator_resolve_wallet_credentials

  if [[ -n "$WALLET_PRIVATE_KEY" && -n "$WALLET_MNEMONIC" ]]; then
    die "Use either --private-key or --mnemonic, not both"
  fi

  if [[ -n "$WALLET_PRIVATE_KEY" ]]; then
    KEYRING_BACKEND=test
  fi

  if [[ -n "$WALLET_ADDRESS" && -z "$WALLET_MNEMONIC" && -z "$WALLET_PRIVATE_KEY" && "$MNEMONIC_STDIN" != "1" && "$PRIVATE_KEY_STDIN" != "1" ]]; then
    if ! "$BINARY" keys show validator --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND" &>/dev/null; then
      die "Wallet key required for $WALLET_ADDRESS. Use --private-key, --mnemonic, or run without --address."
    fi
  fi

  if [[ -n "$WALLET_PRIVATE_KEY" ]]; then
    echo "==> Importing wallet from private key..."
    local hex="${WALLET_PRIVATE_KEY#0x}"
    if "$BINARY" keys show validator --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND" &>/dev/null; then
      echo "    Key 'validator' already exists in keyring"
    else
      "$BINARY" keys import-hex validator "$hex" \
        --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND"
    fi
  elif [[ -n "$WALLET_MNEMONIC" ]]; then
    echo "==> Recovering wallet from mnemonic..."
    if "$BINARY" keys show validator --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND" &>/dev/null; then
      echo "    Key 'validator' already exists in keyring"
    else
      printf '%s\n' "$WALLET_MNEMONIC" | "$BINARY" keys add validator --recover \
        --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND"
    fi
  elif ! "$BINARY" keys show validator --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND" &>/dev/null; then
    echo "==> Creating new validator wallet..."
    "$BINARY" keys add validator --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND"
    echo ""
    echo "    IMPORTANT: Save the mnemonic above securely!"
    echo ""
  fi

  local addr
  addr="$("$BINARY" keys show validator -a --home "$VALIDATOR_HOME" --keyring-backend "$KEYRING_BACKEND")"
  if [[ -n "$WALLET_ADDRESS" && "$addr" != "$WALLET_ADDRESS" ]]; then
    die "Recovered address ($addr) does not match --address ($WALLET_ADDRESS)"
  fi
  WALLET_ADDRESS="$addr"
}

setup_node() {
  [[ -n "${SEED_IP:-}" ]] || die "SEED_IP not set. Export SEED_IP or edit config/validator-network.env"

  mkdir -p "$VALIDATOR_HOME"
  if [[ ! -f "$VALIDATOR_HOME/config/genesis.json" ]]; then
    echo "==> Initializing node..."
    "$BINARY" init "$MONIKER" --chain-id "$CHAIN_ID" --home "$VALIDATOR_HOME"
  fi

  if [[ -n "${VALIDATOR_CONFIG_BACKUP:-}" ]]; then
    validator_restore_config_backup "$VALIDATOR_HOME" "$VALIDATOR_CONFIG_BACKUP" || true
  elif [[ "${RESTORE_CONFIG_FROM_SEED:-0}" == "1" ]]; then
    validator_try_fetch_config_from_seed "$VALIDATOR_HOME" || true
  fi

  local genesis_src=""
  for candidate in \
    "$ROOT_DIR/config/genesis.sudo99.json" \
    "$CHAIN_ROOT/config/genesis.sudo99.json" \
    "${GENESIS_SRC:-}"; do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      genesis_src="$candidate"
      break
    fi
  done
  echo "==> Fetching genesis..."
  if ! validator_fetch_live_genesis "$VALIDATOR_HOME/config/genesis.json" "$ROOT_DIR"; then
    [[ -n "$genesis_src" ]] || die "genesis not found. Set SEED_IP or GENESIS_SRC"
    cp "$genesis_src" "$VALIDATOR_HOME/config/genesis.json"
  fi

  # Exported genesis may include bonded+jailed validators (runtime OK; CLI validate rejects).
  if [[ "${VALIDATE_GENESIS:-0}" == "1" ]]; then
    "$BINARY" genesis validate-genesis --home "$VALIDATOR_HOME"
  else
    echo "==> Skipping validate-genesis (network export may include jailed validators)"
  fi

  local peer="${SEED_NODE_ID}@${SEED_IP}:${SEED_P2P_PORT}"
  local ext_ip
  ext_ip="$(validator_detect_public_ip)"
  validator_configure_node \
    "$VALIDATOR_HOME/config/config.toml" \
    "$VALIDATOR_HOME/config/app.toml" \
    "$peer" \
    "$ext_ip"
  validator_disable_statesync "$VALIDATOR_HOME/config/config.toml"

  echo "==> Node configured | peer=$peer | external=${ext_ip:-auto}"
}

main() {
  parse_args "$@"
  validator_load_network_defaults "$ROOT_DIR"
  validator_open_firewall
  validator_load_deploy_env "$ROOT_DIR"
  BINARY="$(validator_ensure_sudod_binary "$ROOT_DIR")" \
    || die "Could not get sudod binary. Check SUDOD_DOWNLOAD_URL in config/validator-network.env"

  echo ""
  echo "  SUDO Validator — automatic join"
  echo "  Chain: $CHAIN_ID | Stake required: ${STAKE_SUDO} SUDO"
  echo "  Binary: $BINARY"
  echo ""

  validator_install_deps
  export PATH="$PATH:/usr/local/go/bin"

  setup_node
  ensure_wallet_key

  local min_bash already_registered=0
  min_bash="$(validator_min_balance_bash)"

  if validator_is_registered "$BINARY" "$VALIDATOR_HOME"; then
    already_registered=1
    echo "==> Validator already registered on-chain — skipping balance wait + create-validator"
  fi

  if [[ "$already_registered" == "0" ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  FUND THIS WALLET with >= ${STAKE_SUDO} SUDO (+ small fee buffer):"
    echo ""
    echo "    $WALLET_ADDRESS"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local balance
    balance="$(validator_get_balance_bash "$BINARY" "$WALLET_ADDRESS" || echo 0)"
    local balance_sudo
    balance_sudo="$(python3 -c "print(round(int('${balance:-0}')/10**9, 9))")"
    echo "  Current balance: ${balance_sudo} SUDO"

    if python3 -c "exit(0 if int('${balance:-0}') >= int('${min_bash}') else 1)"; then
      echo "==> Balance sufficient — continuing..."
    elif [[ "$WAIT_FOR_FUNDS" == "1" ]]; then
      validator_wait_for_balance "$BINARY" "$WALLET_ADDRESS" "$min_bash"
      echo "==> Balance OK — starting validator setup..."
    else
      die "Insufficient balance. Need >= $(python3 -c "print(${min_bash}/10**9)") SUDO on $WALLET_ADDRESS"
    fi
  fi

  export KEYRING_BACKEND

  if [[ "$already_registered" == "1" ]]; then
    validator_reset_chain_data "$BINARY" "$VALIDATOR_HOME"
  fi

  echo ""
  echo "==> Step 1/4: Starting node (block sync from seed)..."
  validator_start_node_bg "$BINARY" "$VALIDATOR_HOME"

  if [[ "$already_registered" == "0" ]]; then
    echo "==> Step 2/4: Registering validator on-chain (${STAKE_SUDO} SUDO stake)..."
    validator_register "$BINARY" "$VALIDATOR_HOME" "$MONIKER"
    sleep 6
    if ! validator_is_registered "$BINARY" "$VALIDATOR_HOME"; then
      echo "WARN: create-validator submitted but not yet bonded — will recheck after sync"
    fi
  fi

  echo "==> Step 3/4: Waiting for block sync (may take 30-90 min)..."
  if ! validator_wait_for_sync "$RPC_PORT" "${SYNC_MAX_WAIT:-7200}"; then
    echo ""
    echo "ERROR: Node failed to start or sync."
    echo "  Check logs: tail -50 $VALIDATOR_HOME/node.log"
    echo "  Then re-run: bash install-validator.sh"
    exit 1
  fi

  if [[ "$already_registered" == "0" ]]; then
    if ! validator_is_registered "$BINARY" "$VALIDATOR_HOME"; then
      echo "WARN: Validator not bonded yet — check: tail -50 $VALIDATOR_HOME/node.log"
    fi
  fi

  validator_unjail_if_needed "$BINARY" "$VALIDATOR_HOME" "validator" || \
    echo "WARN: unjail failed — run: sudod tx slashing unjail --from validator --home $VALIDATOR_HOME --keyring-backend test --node tcp://170.64.178.165:26657 -y"

  echo "==> Step 4/4: Installing systemd service..."
  if [[ "$INSTALL_SYSTEMD" == "1" ]] && command -v systemctl >/dev/null 2>&1; then
    validator_install_systemd "$BINARY" "$VALIDATOR_HOME"
  else
    echo "==> Node running in background (pid $(cat "$VALIDATOR_HOME/node.pid"))"
    echo "    Logs: $VALIDATOR_HOME/node.log"
  fi

  validator_print_success "$BINARY" "$VALIDATOR_HOME"
}

main "$@"
