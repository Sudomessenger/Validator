#!/usr/bin/env bash
# App backend entry point — deploy validator on USER's VPS (not on worker itself).
#
# Usage (from /opt/validator-worker):
#   ./scripts/deploy-from-app.sh \
#     --server-ip 1.2.3.4 \
#     --password 'ssh-password' \
#     --mnemonic "word1 word2 ... word24" \
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
