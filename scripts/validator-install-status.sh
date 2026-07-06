#!/usr/bin/env bash
# Check validator install / node status.
set -euo pipefail

VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
LOG_FILE="${VALIDATOR_INSTALL_LOG:-/var/log/sudo-validator-install.log}"
PID_FILE="${VALIDATOR_INSTALL_PID:-/var/run/sudo-validator-install.pid}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

echo "=== SUDO Validator Status ==="
echo ""

if [[ -f "$PID_FILE" ]]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "Install script: RUNNING (PID $pid)"
  else
    echo "Install script: finished (stale PID file)"
  fi
else
  echo "Install script: no PID file"
fi

if [[ -f "$LOG_FILE" ]]; then
  echo ""
  echo "Last 15 log lines ($LOG_FILE):"
  tail -15 "$LOG_FILE" 2>/dev/null || true
fi

echo ""
if systemctl is-active sudo-validator &>/dev/null; then
  echo "systemd sudo-validator: active"
  systemctl status sudo-validator --no-pager 2>/dev/null | head -8 || true
elif [[ -f "$VALIDATOR_HOME/node.pid" ]] && kill -0 "$(cat "$VALIDATOR_HOME/node.pid")" 2>/dev/null; then
  echo "Node process: running (pid $(cat "$VALIDATOR_HOME/node.pid"))"
else
  echo "Node: not running via systemd or node.pid"
fi

echo ""
if curl -sf --max-time 5 localhost:26657/status >/tmp/vstat.json 2>/dev/null; then
  python3 -c "
import json
d=json.load(open('/tmp/vstat.json'))['result']
s=d['sync_info']
print('RPC: OK')
print('  height:', s['latest_block_height'])
print('  catching_up:', s['catching_up'])
print('  moniker:', d['node_info']['moniker'])
"
else
  echo "RPC: not responding on :26657"
  if [[ -f "$VALIDATOR_HOME/node.log" ]]; then
    echo ""
    echo "node.log tail:"
    tail -8 "$VALIDATOR_HOME/node.log" 2>/dev/null || true
  fi
fi

echo ""
chain_root="$REPO_ROOT"
sudod_candidates=(
  "${SUDOD_BIN:-}"
  "$REPO_ROOT/build/sudod"
)
SUDOD=""
for candidate in "${sudod_candidates[@]}"; do
  [[ -n "$candidate" && -x "$candidate" ]] || continue
  SUDOD="$candidate"
  break
done
if [[ -n "$SUDOD" ]]; then
  if "$SUDOD" keys show validator -a --home "$VALIDATOR_HOME" --keyring-backend test &>/dev/null \
    || "$SUDOD" keys show validator -a --home "$VALIDATOR_HOME" --keyring-backend file &>/dev/null; then
    addr="$("$SUDOD" keys show validator -a --home "$VALIDATOR_HOME" --keyring-backend test 2>/dev/null \
      || "$SUDOD" keys show validator -a --home "$VALIDATOR_HOME" --keyring-backend file)"
    echo "Wallet: $addr"
    curl -sf "https://lcd.sudoscan.io/cosmos/bank/v1beta1/balances/${addr}" 2>/dev/null \
      | python3 -c "import sys,json; b=json.load(sys.stdin).get('balances',[]); print('Balance:', next((x['amount'] for x in b if x['denom']=='bash'), '0'), 'bash')" \
      2>/dev/null || true
  fi
fi
