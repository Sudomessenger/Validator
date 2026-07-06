#!/usr/bin/env bash
# One-command SUDO validator install — run from this repo root after git clone.
#
# Foreground (terminal must stay open):
#   VALIDATOR_PRIVATE_KEY=0x... bash install-validator.sh
#
# Background (terminal close safe — RECOMMENDED for VPS/web SSH):
#   VALIDATOR_PRIVATE_KEY=0x... bash install-validator.sh --background
#   tail -f /var/log/sudo-validator-install.log
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT

LOG_FILE="${VALIDATOR_INSTALL_LOG:-/var/log/sudo-validator-install.log}"
PID_FILE="${VALIDATOR_INSTALL_PID:-/var/run/sudo-validator-install.pid}"

run_install() {
  bash "$REPO_ROOT/scripts/bootstrap-validator.sh" "$@"
}

if [[ "${1:-}" == "--background" || "${1:-}" == "--detached" ]]; then
  shift
  mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$PID_FILE")"
  if [[ -f "$PID_FILE" ]]; then
    old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      echo "Install already running (PID $old_pid)"
      echo "Monitor: tail -f $LOG_FILE"
      exit 0
    fi
  fi
  echo "Starting validator install in background (terminal can close)..."
  echo "Log file: $LOG_FILE"
  nohup env VALIDATOR_PRIVATE_KEY="${VALIDATOR_PRIVATE_KEY:-}" \
    VALIDATOR_MNEMONIC="${VALIDATOR_MNEMONIC:-}" \
    MONIKER="${MONIKER:-}" \
    VALIDATOR_HOME="${VALIDATOR_HOME:-}" \
    REPO_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/install-validator.sh" "$@" >>"$LOG_FILE" 2>&1 &
  echo $! >"$PID_FILE"
  disown 2>/dev/null || true
  echo "PID: $(cat "$PID_FILE")"
  echo ""
  echo "Monitor progress:"
  echo "  tail -f $LOG_FILE"
  echo ""
  echo "Check status:"
  echo "  bash $REPO_ROOT/scripts/validator-install-status.sh"
  exit 0
fi

if [[ "${1:-}" == "--status" ]]; then
  exec bash "$REPO_ROOT/scripts/validator-install-status.sh"
fi

run_install "$@"
