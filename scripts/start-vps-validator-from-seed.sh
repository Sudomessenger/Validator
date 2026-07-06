#!/usr/bin/env bash
# Seed (170.64.178.165) se VPS validator start karo.
# Usage: SSHPASS='your-vps-password' bash sudo-chain/scripts/start-vps-validator-from-seed.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VALIDATOR_IP="${VALIDATOR_IP:-147.93.153.13}"
VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
SEED_HOME="${SEED_HOME:-/tmp/sudo-localnet}"
SUDOD_SEED="${SUDOD_BIN:-$CHAIN_ROOT/build/sudod}"
VPS_START_SCRIPT="${SCRIPT_DIR}/start-vps-validator-now.sh"
export PM2_HOME="${PM2_HOME:-/root/.pm2}"

ssh_v() {
  if [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null; then
    sshpass -e ssh -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 "root@${VALIDATOR_IP}" "$@"
  else
    ssh -T -o StrictHostKeyChecking=no -o ConnectTimeout=30 "root@${VALIDATOR_IP}" "$@"
  fi
}

scp_v() {
  local src="$1" dst="$2"
  if [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null; then
    sshpass -e scp -o StrictHostKeyChecking=no "$src" "root@${VALIDATOR_IP}:${dst}"
  else
    scp -o StrictHostKeyChecking=no "$src" "root@${VALIDATOR_IP}:${dst}"
  fi
}

echo "=============================================="
echo "  Start VPS validator from seed"
echo "  VPS: $VALIDATOR_IP"
echo "=============================================="

[[ -f "$SEED_HOME/config/genesis.json" ]] || { echo "ERROR: seed genesis missing at $SEED_HOME"; exit 1; }
[[ -x "$SUDOD_SEED" ]] || { echo "ERROR: sudod not found at $SUDOD_SEED (run: cd sudo-chain && make build)"; exit 1; }

ssh_v 'echo VPS ok: $(hostname)' || {
  echo "ERROR: SSH to $VALIDATOR_IP failed."
  echo "  Set password: SSHPASS='...' bash $0"
  echo "  Or on VPS: bash sudo-chain/scripts/start-vps-validator-now.sh"
  exit 1
}

echo "==> 1/5 Seed backup (safety)"
"$SCRIPT_DIR/backup-chain.sh" 2>/dev/null || echo "WARN: backup skipped"

echo "==> 2/5 Copy matching genesis + sudod to VPS"
scp_v "$SEED_HOME/config/genesis.json" "$VALIDATOR_HOME/config/genesis.json"
ssh_v "mkdir -p /home/sudo-chain/sudo-chain/build /home/sudo-chain/sudo-chain/scripts"
scp_v "$SUDOD_SEED" "/home/sudo-chain/sudo-chain/build/sudod"
scp_v "$VPS_START_SCRIPT" "/home/sudo-chain/sudo-chain/scripts/start-vps-validator-now.sh"
ssh_v "chmod +x /home/sudo-chain/sudo-chain/build/sudod /home/sudo-chain/sudo-chain/scripts/start-vps-validator-now.sh"

echo "==> 3/5 Start validator on VPS (block sync from seed)"
ssh_v 'bash /home/sudo-chain/sudo-chain/scripts/start-vps-validator-now.sh'

echo "==> 4/5 Wait for peer + sync (60s)"
sleep 60
ssh_v 'curl -sf localhost:26657/status | python3 -c "
import sys,json
d=json.load(sys.stdin)[\"result\"][\"sync_info\"]
print(\"VPS height:\", d[\"latest_block_height\"], \"catching_up:\", d[\"catching_up\"])
"' || echo "VPS RPC not ready — ssh root@$VALIDATOR_IP journalctl -u sudo-validator -f"

unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY
curl -sf --noproxy '*' http://127.0.0.1:26657/net_info 2>/dev/null | python3 -c "
import sys,json
r=json.load(sys.stdin)['result']
print('Seed peers:', r['n_peers'])
for p in r.get('peers',[]):
    print(' ', p['node_info']['moniker'], p['remote_ip'])
" 2>/dev/null || true

echo ""
echo "==> 5/5 After catching_up=false — unjail on VPS if needed:"
echo "  bash sudo-chain/scripts/unjail-validator.sh   # (on VPS, after git pull)"
echo "Monitor: ssh root@$VALIDATOR_IP 'journalctl -u sudo-validator -f'"
