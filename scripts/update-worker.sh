#!/usr/bin/env bash
# Update validator worker to latest scripts from GitHub.
set -euo pipefail
ROOT="${1:-/opt/validator-worker}"
cd "$ROOT"
echo "==> Updating $ROOT ..."
git fetch origin main
git merge --ff-only origin/main || git pull --ff-only origin main
git log -1 --oneline
echo "OK: worker updated — retry deploy from app"
