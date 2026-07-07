#!/usr/bin/env bash
# Re-apply systemd + sync watchdog on existing validator VPS.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/validator-common.sh"
export REPO_ROOT="$ROOT"
VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
validator_load_network_defaults "$ROOT"
BINARY="$(validator_ensure_sudod_binary "$ROOT" | tail -1)"
validator_install_systemd "$BINARY" "$VALIDATOR_HOME"
echo "OK: 24/7 sync watchdog active"
systemctl status sudo-validator-sync-watch.timer --no-pager | head -5
