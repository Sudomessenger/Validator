#!/usr/bin/env bash
# Keep validator node synced — restart if RPC down or sync stalled.
set -euo pipefail

VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
SERVICE="${VALIDATOR_SYSTEMD_SERVICE:-sudo-validator}"
STATE_DIR="${VALIDATOR_HOME}/.watchdog"
STALL_FILE="${STATE_DIR}/last_height"
MAX_LAG_BLOCKS="${VALIDATOR_MAX_LAG_BLOCKS:-500}"
LOG_TAG="[sudo-validator-watchdog]"

mkdir -p "$STATE_DIR"

log() { echo "$(date -Is) $LOG_TAG $*" | tee -a "${VALIDATOR_HOME}/watchdog.log"; }

restart_node() {
  log "restarting $SERVICE — $1"
  systemctl restart "$SERVICE" || true
  rm -f "$STALL_FILE"
}

if ! systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
  log "service not active — starting $SERVICE"
  systemctl start "$SERVICE" || true
  exit 0
fi

if ! curl -sf --max-time 10 http://127.0.0.1:26657/status >/tmp/sudo-watch-status.json 2>/dev/null; then
  restart_node "RPC not responding on :26657"
  exit 0
fi

height="$(jq -r '.result.sync_info.latest_block_height // 0' /tmp/sudo-watch-status.json)"
catching_up="$(jq -r '.result.sync_info.catching_up // true' /tmp/sudo-watch-status.json)"

if [[ "${height:-0}" == "0" ]]; then
  restart_node "height stuck at 0"
  exit 0
fi

# Detect sync stall: same height across 3 checks (~15 min) while catching_up
if [[ -f "$STALL_FILE" ]]; then
  last_height="$(cat "$STALL_FILE" 2>/dev/null || echo 0)"
  if [[ "$height" == "$last_height" && "$catching_up" == "true" ]]; then
    stall_count="$(cat "${STALL_FILE}.count" 2>/dev/null || echo 0)"
    stall_count=$((stall_count + 1))
    echo "$stall_count" > "${STALL_FILE}.count"
    if [[ "$stall_count" -ge 3 ]]; then
      restart_node "sync stalled at height $height (catching_up=$catching_up)"
      exit 0
    fi
  else
    echo "0" > "${STALL_FILE}.count"
  fi
fi
echo "$height" > "$STALL_FILE"

# Optional: restart if too far behind network LCD
lcd="${PUBLIC_LCD:-https://lcd.sudoscan.io}"
net_height="$(curl -sf --max-time 10 "${lcd}/cosmos/base/tendermint/v1beta1/blocks/latest" 2>/dev/null \
  | jq -r '.block.header.height // empty' || true)"
if [[ -n "$net_height" && "$net_height" =~ ^[0-9]+$ ]]; then
  lag=$((net_height - height))
  if [[ "$lag" -gt "$MAX_LAG_BLOCKS" ]]; then
    restart_node "lag ${lag} blocks behind network (local=$height network=$net_height)"
    exit 0
  fi
fi

log "OK height=$height catching_up=$catching_up"
exit 0
