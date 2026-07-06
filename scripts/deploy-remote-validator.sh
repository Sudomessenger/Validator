#!/usr/bin/env bash
# Deploy validator to a remote server (app-style: server IP + password + mnemonic).
#
# Usage:
#   ./scripts/deploy-remote-validator.sh \
#     --server-ip 1.2.3.4 \
#     --user root \
#     --password 'your-ssh-password' \
#     --mnemonic "word1 word2 ... word24" \
#     --moniker my-validator
#
# Requires: sshpass (apt install sshpass)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SERVER_IP=""
SERVER_USER="root"
SERVER_PASSWORD=""
MNEMONIC=""
PRIVATE_KEY=""
MONIKER="sudo-validator"
REPO_URL="${REPO_URL:-https://github.com/Sudomessenger/Validator.git}"

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-ip) SERVER_IP="$2"; shift 2 ;;
    --user) SERVER_USER="$2"; shift 2 ;;
    --password) SERVER_PASSWORD="$2"; shift 2 ;;
    --mnemonic) MNEMONIC="$2"; shift 2 ;;
    --private-key) PRIVATE_KEY="$2"; shift 2 ;;
    --moniker) MONIKER="$2"; shift 2 ;;
    --repo) REPO_URL="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -n "$SERVER_IP" ]] || die "Missing --server-ip"
[[ -n "$SERVER_PASSWORD" ]] || die "Missing --password"
[[ -n "$MNEMONIC" || -n "$PRIVATE_KEY" ]] || die "Missing --mnemonic or --private-key"
[[ -z "$MNEMONIC" || -z "$PRIVATE_KEY" ]] || die "Use either --mnemonic or --private-key, not both"
command -v sshpass >/dev/null 2>&1 || die "Install sshpass: sudo apt install -y sshpass"

# Escape for safe embedding in remote single-quoted string
escape_sq() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }
MNEMONIC_ESC="$(escape_sq "$MNEMONIC")"
PRIVATE_KEY_ESC="$(escape_sq "$PRIVATE_KEY")"
MONIKER_ESC="$(escape_sq "$MONIKER")"

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30"
REMOTE="sshpass -p $(printf '%q' "$SERVER_PASSWORD") ssh $SSH_OPTS ${SERVER_USER}@${SERVER_IP}"

echo "==> Deploying SUDO validator to ${SERVER_USER}@${SERVER_IP} ..."

eval "$REMOTE" bash -s <<REMOTE_SCRIPT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/false
export VALIDATOR_HOME=/opt/sudo-validator
export SUDO_LIB_DIR=/usr/local/lib/sudo
export LD_LIBRARY_PATH=/usr/local/lib/sudo
export KEYRING_BACKEND=test
export MONIKER='${MONIKER_ESC}'
export WAIT_FOR_FUNDS=1

rm -rf /opt/sudo-chain-deploy
git clone --depth 1 '${REPO_URL}' /opt/sudo-chain-deploy
cd /opt/sudo-chain-deploy
chmod +x join-validator.sh scripts/*.sh scripts/lib/*.sh 2>/dev/null || true

if [[ -n '${PRIVATE_KEY_ESC}' ]]; then
  export VALIDATOR_PRIVATE_KEY='${PRIVATE_KEY_ESC}'
else
  export VALIDATOR_MNEMONIC='${MNEMONIC_ESC}'
fi

./join-validator.sh --moniker '${MONIKER_ESC}'
REMOTE_SCRIPT

echo ""
echo "==> Remote deploy finished. Check status:"
echo "    ssh ${SERVER_USER}@${SERVER_IP} 'sudo systemctl status sudo-validator'"
echo "    https://sudoscan.io/validators"
