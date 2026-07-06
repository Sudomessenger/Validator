#!/usr/bin/env bash
# App backend entry point — deploy validator on USER's VPS (not on worker itself).
#
# Usage (from /opt/validator-worker):
#   # Option A — mnemonic:
#   ./scripts/deploy-from-app.sh \
#     --server-ip 1.2.3.4 \
#     --password 'ssh-password' \
#     --mnemonic "word1 word2 ... word24" \
#     --moniker my-validator
#
#   # Option B — private key (64 hex chars, 0x optional):
#   ./scripts/deploy-from-app.sh \
#     --server-ip 1.2.3.4 \
#     --password 'ssh-password' \
#     --private-key '0xYOUR_64_HEX_PRIVATE_KEY' \
#     --moniker my-validator
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ "${VALIDATOR_SKIP_GIT_PULL:-0}" != "1" && -d "$ROOT/.git" ]]; then
  git fetch origin main -q 2>/dev/null || true
  git merge --ff-only origin/main -q 2>/dev/null || git pull --ff-only origin main -q 2>/dev/null || true
fi
exec "$ROOT/scripts/deploy-remote-validator.sh" "$@"
