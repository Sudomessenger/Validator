#!/usr/bin/env bash
# Production bootstrap — fresh or reset validator VPS (zero manual steps).
#
# First time on a new Ubuntu VPS:
#   git clone https://github.com/Sudomessenger/Validator.git /opt/sudo-validator-deploy
#   cd /opt/sudo-validator-deploy
#   cp config/validator-deploy.env.example config/validator-deploy.env
#   # edit validator-deploy.env — set VALIDATOR_PRIVATE_KEY or VALIDATOR_MNEMONIC
#   bash install-validator.sh
#
# Or one-liner with private key:
#   VALIDATOR_PRIVATE_KEY=0x... bash install-validator.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/lib/validator-common.sh"

die() { echo "ERROR: $*" >&2; exit 1; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  SUDO Validator — production bootstrap                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

validator_load_network_defaults "$REPO_ROOT"
validator_load_deploy_env "$REPO_ROOT"

JOIN_ARGS=()
if [[ -n "${VALIDATOR_PRIVATE_KEY:-}" ]]; then
  if validator_credential_looks_like_mnemonic "$VALIDATOR_PRIVATE_KEY"; then
    JOIN_ARGS+=(--mnemonic "$VALIDATOR_PRIVATE_KEY")
  else
    JOIN_ARGS+=(--private-key "$VALIDATOR_PRIVATE_KEY")
  fi
elif [[ -n "${VALIDATOR_MNEMONIC:-}" ]]; then
  JOIN_ARGS+=(--mnemonic "$VALIDATOR_MNEMONIC")
elif [[ -n "${1:-}" ]]; then
  JOIN_ARGS+=("$@")
fi

if [[ ${#JOIN_ARGS[@]} -eq 0 ]] \
  && [[ ! -f "$REPO_ROOT/config/validator-deploy.env" ]]; then
  cat <<EOF
No wallet credentials found.

Option A — env file (recommended for production):
  cp config/validator-deploy.env.example config/validator-deploy.env
  nano config/validator-deploy.env
  bash install-validator.sh

Option B — inline private key:
  VALIDATOR_PRIVATE_KEY=0x... bash install-validator.sh

Option C — stdin:
  echo "YOUR_HEX_KEY" | bash join-validator.sh --private-key-stdin

EOF
  exit 1
fi

validator_install_deps
validator_open_firewall

BINARY="$(validator_ensure_sudod_binary "$REPO_ROOT")" \
  || die "Could not get sudod binary. Check SUDOD_DOWNLOAD_URL in config/validator-network.env"

export MONIKER="${MONIKER:-sudo-validator}"
export VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
export INSTALL_SYSTEMD="${INSTALL_SYSTEMD:-1}"
export WAIT_FOR_FUNDS="${WAIT_FOR_FUNDS:-1}"

exec "$REPO_ROOT/scripts/join-validator.sh" \
  --moniker "$MONIKER" \
  "${JOIN_ARGS[@]}"
