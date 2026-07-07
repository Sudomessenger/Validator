#!/usr/bin/env bash
# Run ONCE on the SEED server (170.64.178.165) to enable snapshot creation.
# New validator deploys use state sync (~5-15 min) instead of block sync (hours).
#
# Usage (on seed server):
#   cd /opt/validator-worker   # or wherever Validator repo is cloned
#   git pull origin main
#   bash scripts/enable-seed-snapshots.sh
#
# Optional env:
#   SEED_HOME=/tmp/sudo-localnet
#   STATE_SYNC_SNAPSHOT_INTERVAL=1000
#   STATE_SYNC_SNAPSHOT_KEEP=5
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/validator-common.sh"

validator_load_network_defaults "$ROOT_DIR"

SEED_HOME="${SEED_HOME:-/tmp/sudo-localnet}"
APP_TOML="$SEED_HOME/config/app.toml"
CONFIG_TOML="$SEED_HOME/config/config.toml"
INTERVAL="${STATE_SYNC_SNAPSHOT_INTERVAL:-1000}"
KEEP="${STATE_SYNC_SNAPSHOT_KEEP:-5}"

die() { echo "ERROR: $*" >&2; exit 1; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  SUDO Seed — enable snapshots for state sync                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  SEED_HOME=$SEED_HOME"
echo "  snapshot-interval=$INTERVAL  keep-recent=$KEEP"
echo ""

[[ -f "$APP_TOML" ]] || die "app.toml not found: $APP_TOML (set SEED_HOME)"

echo "==> 1/4 Backing up app.toml..."
cp -a "$APP_TOML" "${APP_TOML}.bak.$(date +%Y%m%d%H%M%S)"

echo "==> 2/4 Enabling snapshot creation in app.toml..."
validator_enable_seed_snapshots "$APP_TOML" "$INTERVAL" "$KEEP"
grep -A3 '^\[state-sync\]' "$APP_TOML" || grep -E 'snapshot-interval|snapshot-keep-recent' "$APP_TOML" || true

if [[ -f "$CONFIG_TOML" ]]; then
  echo "==> Ensuring RPC listens on 0.0.0.0:26657 (state sync clients)..."
  sed -i 's|^laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|' "$CONFIG_TOML" || true
fi

echo "==> 3/4 Restarting seed node..."
if systemctl is-active --quiet sudo-validator 2>/dev/null; then
  systemctl restart sudo-validator
  sleep 8
  systemctl status sudo-validator --no-pager | head -10 || true
elif command -v pm2 >/dev/null 2>&1 && pm2 describe sudod >/dev/null 2>&1; then
  pm2 restart sudod
  sleep 8
else
  echo "    WARN: No sudo-validator systemd/pm2 service found."
  echo "    Restart sudod manually so snapshot-interval takes effect."
fi

echo "==> 4/4 Verify (snapshots appear after ~$INTERVAL blocks)..."
sleep 3
if curl -sf --max-time 10 "http://127.0.0.1:26657/status" >/tmp/seed-status.json 2>/dev/null; then
  python3 -c "
import json
s=json.load(open('/tmp/seed-status.json'))['result']['sync_info']
print('  Seed height:', s['latest_block_height'], '| catching_up:', s['catching_up'])
"
else
  echo "    WARN: Seed RPC not responding on :26657"
fi

if [[ -d "$SEED_HOME/data/snapshots" ]]; then
  count="$(find "$SEED_HOME/data/snapshots" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
  echo "  Existing snapshots in data/snapshots: $count"
else
  echo "  data/snapshots/ not created yet — normal until next snapshot-interval blocks."
fi

echo ""
echo "Done. After ~$INTERVAL new blocks, seed will serve state-sync snapshots."
echo "New validator deploys auto-use state sync (USE_STATE_SYNC=1 default)."
echo ""
