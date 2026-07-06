#!/usr/bin/env bash
# Validator VPS — update code + resync (existing node).
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"

cd "$REPO_ROOT"
git pull origin main

export REPO_ROOT VALIDATOR_HOME
bash "$REPO_ROOT/scripts/start-vps-validator-now.sh"
