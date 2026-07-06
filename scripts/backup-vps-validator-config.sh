#!/usr/bin/env bash
# Run on SEED before resetting validator VPS — backs up consensus keys for redeploy.
set -euo pipefail

VALIDATOR_IP="${VALIDATOR_IP:-147.93.153.13}"
VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
BACKUP_DIR="${BACKUP_DIR:-/root/sudo-backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="$BACKUP_DIR/vps-validator-config-${STAMP}.tar.gz"
LATEST="$BACKUP_DIR/vps-validator-config-latest.tar.gz"

mkdir -p "$BACKUP_DIR"

ssh_v() {
  if [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null; then
    sshpass -e ssh -T -o StrictHostKeyChecking=no "root@${VALIDATOR_IP}" "$@"
  else
    ssh -T -o StrictHostKeyChecking=no "root@${VALIDATOR_IP}" "$@"
  fi
}

echo "==> Backing up validator config from $VALIDATOR_IP..."
ssh_v "tar czf - -C $VALIDATOR_HOME config/priv_validator_key.json config/node_key.json config/keyring-file 2>/dev/null || tar czf - -C $VALIDATOR_HOME config/priv_validator_key.json config/node_key.json" > "$ARCHIVE"

cp -f "$ARCHIVE" "$LATEST"
echo "==> Saved: $ARCHIVE"
echo "==> Latest: $LATEST"
echo "Redeploy on fresh VPS will auto-fetch this if SSH from validator to seed works."
