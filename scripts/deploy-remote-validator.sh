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
command -v sshpass >/dev/null 2>&1 || die "Install sshpass: sudo apt install -y sshpass"

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30"
REMOTE="sshpass -p '$SERVER_PASSWORD' ssh $SSH_OPTS ${SERVER_USER}@${SERVER_IP}"

echo "==> Deploying SUDO validator to ${SERVER_USER}@${SERVER_IP} ..."

eval "$REMOTE" "'bash -s'" <<REMOTE_SCRIPT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export GITHUB_TOKEN='${GITHUB_TOKEN:-}'
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/false
apt-get update -qq && apt-get install -y -qq git curl jq python3 build-essential sshpass 2>/dev/null || true
rm -rf /opt/sudo-chain-deploy
git clone --depth 1 '$REPO_URL' /opt/sudo-chain-deploy
cd /opt/sudo-chain-deploy
chmod +x join-validator.sh scripts/*.sh scripts/lib/*.sh 2>/dev/null || true
export VALIDATOR_HOME=/opt/sudo-validator
export MONIKER='$MONIKER'
JOIN_ARGS=""
if [[ -n '$PRIVATE_KEY' ]]; then
  JOIN_ARGS="--private-key '$PRIVATE_KEY'"
else
  JOIN_ARGS="--mnemonic '$MNEMONIC'"
fi
./join-validator.sh \$JOIN_ARGS --no-wait
REMOTE_SCRIPT

echo ""
echo "==> Remote deploy started. Check status:"
echo "    ssh ${SERVER_USER}@${SERVER_IP} 'sudo systemctl status sudo-validator'"
echo "    https://sudoscan.io/validators"
