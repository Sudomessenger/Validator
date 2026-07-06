#!/usr/bin/env bash
# Shared helpers for join-validator / deploy-validator scripts.

set -euo pipefail

# Standalone Validator repo — sudod comes from pre-built download (not network.git).
# Optional source build: SUDO_BUILD_FROM_SOURCE=1 + SUDO_CHAIN_SRC or GITHUB_TOKEN.
SUDO_CHAIN_REPO_URL="${SUDO_CHAIN_REPO_URL:-https://github.com/Sudomessenger/network.git}"
SUDO_CHAIN_REF="${SUDO_CHAIN_REF:-main}"
SUDOD_DOWNLOAD_URL="${SUDOD_DOWNLOAD_URL:-https://github.com/Sudomessenger/Validator/releases/download/v1.0.0/sudod-linux-amd64}"

validator_download_sudod() {
  local repo_root="${1:?}"
  local dest="${2:-$repo_root/build/sudod}"
  local url="${SUDOD_DOWNLOAD_URL:-}"
  local tmp="${dest}.download"

  [[ -n "$url" ]] || {
    validator_load_network_defaults "$repo_root"
    url="${SUDOD_DOWNLOAD_URL:-}"
  }
  [[ -n "$url" ]] || {
    echo "ERROR: SUDOD_DOWNLOAD_URL not set." >&2
    return 1
  }

  echo "==> Downloading pre-built sudod..."
  echo "    URL: $url"
  mkdir -p "$(dirname "$dest")"
  rm -f "$tmp"
  if ! curl -fsSL --connect-timeout 120 --retry 3 --retry-delay 5 "$url" -o "$tmp"; then
    rm -f "$tmp"
    if [[ -n "${SUDOD_DOWNLOAD_FALLBACK_URL:-}" ]]; then
      echo "    Primary failed — trying fallback: $SUDOD_DOWNLOAD_FALLBACK_URL"
      if curl -fsSL --connect-timeout 120 --retry 2 "$SUDOD_DOWNLOAD_FALLBACK_URL" -o "$tmp"; then
        :
      else
        rm -f "$tmp"
        echo "ERROR: sudod download failed from $url and fallback." >&2
        echo "       Upload binary: bash scripts/upload-sudod-release.sh" >&2
        return 1
      fi
    else
      echo "ERROR: sudod download failed from $url" >&2
      echo "       Create GitHub Release v1.0.0 with asset sudod-linux-amd64" >&2
      echo "       Or: bash scripts/upload-sudod-release.sh" >&2
      return 1
    fi
  fi
  mv "$tmp" "$dest"
  chmod +x "$dest"
  if ! "$dest" version >/dev/null 2>&1 && ! "$dest" --help >/dev/null 2>&1; then
    echo "ERROR: downloaded file is not a valid sudod binary." >&2
    rm -f "$dest"
    return 1
  fi
  echo "==> sudod ready: $dest"
  return 0
}

validator_ensure_sudod_binary() {
  local repo_root="${1:?}"
  local binary
  binary="$(validator_find_sudod_binary "$repo_root" "$repo_root")"

  if [[ -x "$binary" && "$binary" != "$repo_root/build/sudod" ]] || \
     { [[ -x "$binary" ]] && "$binary" version >/dev/null 2>&1; }; then
    echo "$binary"
    return 0
  fi

  binary="${SUDOD_BIN:-$repo_root/build/sudod}"
  if [[ -x "$binary" ]] && "$binary" version >/dev/null 2>&1; then
    echo "$binary"
    return 0
  fi

  if [[ "${SUDO_BUILD_FROM_SOURCE:-0}" == "1" ]]; then
    local chain_root
    chain_root="$(validator_ensure_chain_source "$repo_root")" \
      || return 1
    validator_build_sudod "$chain_root" "$binary" || return 1
    echo "$binary"
    return 0
  fi

  validator_download_sudod "$repo_root" "$binary" || return 1
  echo "$binary"
}

# Legacy / optional — only when SUDO_BUILD_FROM_SOURCE=1
validator_git_clone_url() {
  local base="${1:-$SUDO_CHAIN_REPO_URL}"
  base="${base%.git}"
  if [[ "$base" == *"@github.com/"* ]]; then
    printf '%s\n' "$base.git"
    return 0
  fi
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    base="${base#https://}"
    base="${base#http://}"
    printf 'https://%s@%s.git\n' "$GITHUB_TOKEN" "$base"
    return 0
  fi
  printf '%s.git\n' "$base"
}

validator_ensure_chain_source() {
  local repo_root="${1:?}"
  local chain_dir="${SUDO_CHAIN_SRC:-$repo_root/.chain/network/sudo-chain}"

  for candidate in \
    "$chain_dir" \
    "$repo_root/sudo-chain" \
    "$repo_root/../network/sudo-chain" \
    "/home/sudo-chain/sudo-chain"; do
    [[ -f "$candidate/go.mod" ]] || continue
    echo "$candidate"
    return 0
  done

  local clone_root="${SUDO_CHAIN_CLONE_ROOT:-$repo_root/.chain/network}"
  local clone_url branch branches=() clone_ok=0
  clone_url="$(validator_git_clone_url "$SUDO_CHAIN_REPO_URL")"

  echo "==> Fetching SUDO chain source for sudod build..."
  echo "    Clone: ${clone_url//$GITHUB_TOKEN/***} (ref: ${SUDO_CHAIN_REF})"
  mkdir -p "$(dirname "$clone_root")"
  rm -rf "$clone_root"

  export GIT_TERMINAL_PROMPT=0
  export GIT_ASKPASS=/bin/false

  branches=("$SUDO_CHAIN_REF")
  [[ "$SUDO_CHAIN_REF" != "main" ]] && branches+=("main")
  branches+=("feat/validator-ops-explorer-sync")

  for branch in "${branches[@]}"; do
    [[ -n "$branch" ]] || continue
    if git clone --depth 1 --branch "$branch" "$clone_url" "$clone_root" 2>/tmp/sudo-chain-clone.err; then
      clone_ok=1
      break
    fi
    rm -rf "$clone_root"
  done

  if [[ "$clone_ok" != "1" ]]; then
    echo "ERROR: git clone failed for Sudomessenger/network." >&2
    sed 's/'"${GITHUB_TOKEN:-___none___}"'/***/g' /tmp/sudo-chain-clone.err >&2 2>/dev/null || cat /tmp/sudo-chain-clone.err >&2
    echo "" >&2
    echo "Fix: export GITHUB_TOKEN=ghp_xxx on the deploy worker (repo is private)." >&2
    echo "     Or set SUDO_CHAIN_SRC=/path/to/local/sudo-chain with go.mod" >&2
    echo "     Or set SUDOD_BIN=/path/to/prebuilt/sudod to skip clone/build." >&2
    return 1
  fi

  chain_dir="$clone_root/sudo-chain"
  if [[ ! -f "$chain_dir/go.mod" && -f "$clone_root/go.mod" ]]; then
    chain_dir="$clone_root"
  fi
  [[ -f "$chain_dir/go.mod" ]] || {
    echo "ERROR: go.mod not found under $clone_root (expected sudo-chain/ or repo root)." >&2
    return 1
  }
  echo "$chain_dir"
}

validator_resolve_chain_root() {
  local root="${1:?}"
  for candidate in \
    "${SUDO_CHAIN_SRC:-}" \
    "$root/sudo-chain" \
    "$root/.chain/network/sudo-chain" \
    "$root/../network/sudo-chain"; do
    [[ -n "$candidate" && -f "$candidate/go.mod" ]] || continue
    echo "$candidate"
    return 0
  done
  validator_ensure_chain_source "$root"
}

validator_find_sudod_binary() {
  local chain_root="${1:?}"
  local root="${2:-}"
  local candidate
  for candidate in \
    "${SUDOD_BIN:-}" \
    "${root:+$root/build/sudod}" \
    "$chain_root/build/sudod" \
    "${root:+$root/sudo-chain/build/sudod}" \
    "${root:+$root/.chain/network/sudo-chain/build/sudod}" \
    "/home/sudo-chain/sudo-chain/build/sudod" \
    "/home/sudo-chain/build/sudod"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    echo "$candidate"
    return 0
  done
  if [[ -n "$root" ]]; then
    echo "$root/build/sudod"
  else
    echo "$chain_root/build/sudod"
  fi
}

validator_load_network_defaults() {
  local root="${1:?}"
  local env_file="$root/config/validator-network.env"
  if [[ -f "$env_file" ]]; then
    # shellcheck disable=SC1090
    source "$env_file"
  fi
  CHAIN_ID="${CHAIN_ID:-sudo99}"
  SEED_NODE_ID="${SEED_NODE_ID:-6eafed75e8db7b0eed2f608b211afde9f71de184}"
  SEED_IP="${SEED_IP:-170.64.178.165}"
  SEED_P2P_PORT="${SEED_P2P_PORT:-26656}"
  PUBLIC_RPC="${PUBLIC_RPC:-https://rpc.sudoscan.io}"
  STAKE_SUDO="${STAKE_SUDO:-1000}"
  FEE_BUFFER_SUDO="${FEE_BUFFER_SUDO:-1}"
}

validator_load_deploy_env() {
  local chain_root="${1:?}"
  local deploy_env=""
  for candidate in \
    "$chain_root/config/validator-deploy.env" \
    "${REPO_ROOT:-}/config/validator-deploy.env"; do
    [[ -n "$candidate" && -f "$candidate" ]] && deploy_env="$candidate" && break
  done
  deploy_env="${deploy_env:-$chain_root/config/validator-deploy.env}"
  if [[ -f "$deploy_env" ]]; then
    # shellcheck disable=SC1090
    source "$deploy_env"
  fi
  KEY_NAME="${KEY_NAME:-validator}"
  MONIKER="${MONIKER:-sudo-validator}"
  VALIDATOR_HOME="${VALIDATOR_HOME:-/opt/sudo-validator}"
  # Normalize credentials from env file
  if [[ -n "${VALIDATOR_PRIVATE_KEY:-}" ]] && validator_credential_looks_like_mnemonic "$VALIDATOR_PRIVATE_KEY"; then
    VALIDATOR_MNEMONIC="$VALIDATOR_PRIVATE_KEY"
    unset VALIDATOR_PRIVATE_KEY
  elif [[ -n "${VALIDATOR_PRIVATE_KEY:-}" ]]; then
    VALIDATOR_PRIVATE_KEY="$(validator_normalize_private_key "$VALIDATOR_PRIVATE_KEY")" || exit 1
  fi
}

validator_normalize_private_key() {
  local raw="${1:?}"
  # Trim whitespace and common quoting
  raw="$(printf '%s' "$raw" | tr -d ' \t\r\n\"'"'"'')"
  raw="${raw#0x}"
  raw="${raw#0X}"

  if [[ "$raw" =~ [^0-9a-fA-F] ]]; then
    echo "ERROR: Private key must be 64 hex characters (0-9, a-f only)." >&2
    echo "       You may have pasted a mnemonic, GitHub token, or wrong value." >&2
    echo "       Use: VALIDATOR_MNEMONIC=\"word1 word2 ...\" bash install-validator.sh" >&2
    echo "       Or:  VALIDATOR_PRIVATE_KEY=0x<64_hex_chars> bash install-validator.sh" >&2
    return 1
  fi
  if [[ ${#raw} -ne 64 ]]; then
    echo "ERROR: Private key must be exactly 64 hex chars (32 bytes), got ${#raw}." >&2
    return 1
  fi
  printf '%s' "$raw"
}

validator_credential_looks_like_mnemonic() {
  local raw="$1"
  [[ "$raw" =~ [[:space:]] ]] && return 0
  [[ "$raw" =~ , ]] && return 0
  return 1
}

validator_resolve_wallet_credentials() {
  # If hex field contains spaces, treat as mnemonic (common user mistake).
  if [[ -n "${WALLET_PRIVATE_KEY:-}" ]] && validator_credential_looks_like_mnemonic "$WALLET_PRIVATE_KEY"; then
    echo "==> Detected mnemonic in private-key field — using mnemonic recovery"
    WALLET_MNEMONIC="$WALLET_PRIVATE_KEY"
    WALLET_PRIVATE_KEY=""
  fi
  if [[ -n "${WALLET_PRIVATE_KEY:-}" ]]; then
    WALLET_PRIVATE_KEY="$(validator_normalize_private_key "$WALLET_PRIVATE_KEY")" \
      || exit 1
  fi
}

validator_open_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -q "Status: active"; then
      echo "==> Opening firewall ports 26656 (P2P) and 26657 (RPC)..."
      ufw allow 26656/tcp comment 'SUDO P2P' >/dev/null 2>&1 || ufw allow 26656/tcp
      ufw allow 26657/tcp comment 'SUDO RPC' >/dev/null 2>&1 || ufw allow 26657/tcp
    fi
  fi
}

validator_scp_nointeract() {
  # Never prompt for password — fail fast if SSH key not configured.
  scp -o BatchMode=yes -o PasswordAuthentication=no \
    -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "$@"
}

validator_write_genesis_json() {
  # Parse CometBFT /genesis RPC response into dest file; print initial_height on success.
  local raw_file="${1:?}"
  local dest="${2:?}"
  python3 - "$raw_file" "$dest" <<'PY'
import json, sys
raw = json.load(open(sys.argv[1]))
g = raw.get("result", raw)
if "genesis" in g:
    g = g["genesis"]
json.dump(g, open(sys.argv[2], "w"), indent=2)
print(g.get("initial_height", "?"))
PY
}

validator_fetch_genesis_from_rpc() {
  local dest="${1:?}"
  local endpoint raw_url hostport base

  local endpoints=()
  if [[ -n "${PUBLIC_TX_NODE:-}" ]]; then
    hostport="${PUBLIC_TX_NODE#tcp://}"
    hostport="${hostport#http://}"
    hostport="${hostport#https://}"
    endpoints+=("http://${hostport}/genesis")
  fi
  if [[ -n "${SEED_IP:-}" ]]; then
    endpoints+=("http://${SEED_IP}:26657/genesis")
  fi
  if [[ -n "${PUBLIC_RPC:-}" ]]; then
    base="${PUBLIC_RPC%/}"
    base="${base#https://}"
    base="${base#http://}"
    endpoints+=("https://${base}/genesis" "http://${base}/genesis")
  fi

  for endpoint in "${endpoints[@]}"; do
    [[ -n "$endpoint" ]] || continue
    echo "==> Fetching genesis from $endpoint ..."
    if curl -sf --max-time 30 "$endpoint" -o "${dest}.tmp" 2>/dev/null \
      && validator_write_genesis_json "${dest}.tmp" "$dest"; then
      rm -f "${dest}.tmp"
      echo "    OK: live genesis (initial_height above)"
      return 0
    fi
    rm -f "${dest}.tmp"
  done

  return 1
}

validator_find_bundled_genesis() {
  local root="${1:-}"
  local candidate bundled=""
  for candidate in \
    "${root}/sudo-chain/config/genesis.sudo99.json" \
    "${root}/config/genesis.sudo99.json"; do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      bundled="$candidate"
      break
    fi
  done
  [[ -n "$bundled" ]] && echo "$bundled"
}

validator_fetch_live_genesis() {
  local dest="${1:?}"
  local root="${2:-}"

  mkdir -p "$(dirname "$dest")"

  # Live genesis first — bundled genesis.sudo99.json is often stale after chain recovery.
  if validator_fetch_genesis_from_rpc "$dest"; then
    return 0
  fi

  local bundled
  bundled="$(validator_find_bundled_genesis "$root" || true)"
  if [[ -n "$bundled" ]]; then
    cp "$bundled" "$dest"
    local ih
    ih="$(python3 -c "import json; print(json.load(open('$dest')).get('initial_height','?'))" 2>/dev/null || echo "?")"
    echo "==> Genesis: bundled fallback ($bundled, initial_height=$ih)"
    echo "    WARN: could not fetch live genesis — sync may fail if bundled height != network"
    return 0
  fi

  # Optional: seed scp only when explicitly enabled (admin redeploy — needs SSH key, not password)
  local seed_ip="${SEED_IP:-}"
  if [[ "${FETCH_GENESIS_FROM_SEED:-0}" == "1" && -n "$seed_ip" ]]; then
    echo "==> Fetching genesis from seed ($seed_ip) [FETCH_GENESIS_FROM_SEED=1]..."
    if validator_scp_nointeract "root@${seed_ip}:/tmp/sudo-localnet/config/genesis.json" "$dest" 2>/dev/null; then
      echo "    OK: genesis from seed"
      return 0
    fi
    echo "    WARN: seed scp failed (set up SSH key or use bundled/RPC genesis)"
  fi

  return 1
}

validator_disable_statesync() {
  local config="${1:?}"
  python3 - "$config" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text = re.sub(r'(\[statesync\][\s\S]*?)^enable = true', r'\1enable = false', text, count=1, flags=re.M)
open(path, 'w').write(text)
PY
}

validator_reset_chain_data() {
  local binary="$1"
  local home="$2"
  echo "==> Resetting block data (keeping keys + addr book)..."
  "$binary" comet unsafe-reset-all --home "$home" --keep-addr-book
  printf '{"height":"0","round":0,"step":0}\n' > "$home/data/priv_validator_state.json"
}

validator_restore_config_backup() {
  local home="$1"
  local backup="${2:-}"
  [[ -n "$backup" && -f "$backup" ]] || return 1
  echo "==> Restoring validator config backup: $backup"
  mkdir -p "$home/config"
  case "$backup" in
    *.tar.gz|*.tgz)
      tar xzf "$backup" -C "$home" --strip-components=0 2>/dev/null \
        || tar xzf "$backup" -C "$home/config" --wildcards '*/priv_validator_key.json' '*/node_key.json' 2>/dev/null \
        || tar xzf "$backup" -C "$home/config" priv_validator_key.json node_key.json 2>/dev/null
      ;;
    *)
      cp "$backup" "$home/config/" 2>/dev/null || return 1
      ;;
  esac
  [[ -f "$home/config/priv_validator_key.json" ]] || return 1
  echo "    OK: consensus keys restored"
  return 0
}

validator_try_fetch_config_from_seed() {
  local home="$1"
  [[ "${RESTORE_CONFIG_FROM_SEED:-0}" == "1" ]] || return 1
  local seed_ip="${SEED_IP:-}"
  local remote="${VALIDATOR_CONFIG_BACKUP_PATH:-/root/sudo-backups/vps-validator-config-latest.tar.gz}"
  [[ -n "$seed_ip" ]] || return 1
  local tmp="/tmp/sudo-validator-config-$$.tar.gz"
  echo "==> Restoring validator config from seed [RESTORE_CONFIG_FROM_SEED=1]..."
  if validator_scp_nointeract "root@${seed_ip}:${remote}" "$tmp" 2>/dev/null; then
    validator_restore_config_backup "$home" "$tmp"
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  echo "    WARN: seed config backup not available (SSH key required on seed)"
  return 1
}

validator_is_jailed() {
  local binary="$1"
  local home="$2"
  local key_name="${3:-validator}"
  local valoper
  valoper="$("$binary" keys show "$key_name" --bech val -a --home "$home" \
    --keyring-backend "${KEYRING_BACKEND:-file}" 2>/dev/null)" || return 1
  local jailed
  jailed="$("$binary" query staking validator "$valoper" \
    --node "$(validator_tx_node)" -o json 2>/dev/null \
    | jq -r '.validator.jailed // false')"
  [[ "$jailed" == "true" ]]
}

validator_unjail_if_needed() {
  local binary="$1"
  local home="$2"
  local key_name="${3:-validator}"
  if ! validator_is_jailed "$binary" "$home" "$key_name"; then
    echo "==> Validator not jailed — skipping unjail"
    return 0
  fi
  echo "==> Validator is jailed — submitting unjail..."
  local tx_node
  tx_node="$(validator_tx_node)"
  local out
  if ! out="$("$binary" tx slashing unjail \
    --from "$key_name" \
    --chain-id "$CHAIN_ID" \
    --home "$home" \
    --keyring-backend "${KEYRING_BACKEND:-file}" \
    --node "$tx_node" \
    --yes -b sync \
    --gas 250000 \
    --fees 250bash 2>&1)"; then
    echo "$out" >&2
    echo "WARN: unjail tx failed — retry with: sudod tx slashing unjail --from $key_name --fees 100bash --gas 200000 ..."
    return 1
  fi
  if echo "$out" | grep -qE '"code":[^0]|code: [1-9]'; then
    echo "$out" >&2
    echo "WARN: unjail tx rejected (check fees/balance above)"
    return 1
  fi
  echo "==> Unjail submitted successfully"
  echo "$out" | tail -3
}

validator_stake_bash() {
  python3 -c "print(int(${STAKE_SUDO}) * 10**9)"
}

validator_min_balance_bash() {
  python3 -c "print(int(${STAKE_SUDO} + ${FEE_BUFFER_SUDO}) * 10**9)"
}

validator_rpc_to_node() {
  local rpc="$1"
  if [[ "$rpc" == https://* ]]; then
    echo "tcp://${rpc#https://}"
  elif [[ "$rpc" == http://* ]]; then
    echo "tcp://${rpc#http://}"
  elif [[ "$rpc" == tcp://* ]]; then
    echo "$rpc"
  else
    echo "tcp://$rpc"
  fi
}

validator_tx_node() {
  if curl -sf --max-time 3 http://127.0.0.1:26657/status >/dev/null 2>&1; then
    echo "tcp://127.0.0.1:26657"
    return 0
  fi
  if [[ -n "${PUBLIC_TX_NODE:-}" ]]; then
    echo "$PUBLIC_TX_NODE"
    return 0
  fi
  if [[ -n "${SEED_IP:-}" ]]; then
    echo "tcp://${SEED_IP}:26657"
    return 0
  fi
  validator_rpc_to_node "${PUBLIC_RPC:-https://rpc.sudoscan.io}"
}

validator_detect_public_ip() {
  if [[ -n "${EXTERNAL_IP:-}" ]]; then
    echo "$EXTERNAL_IP"
    return
  fi
  curl -sf --max-time 5 https://api.ipify.org 2>/dev/null \
    || curl -sf --max-time 5 https://ifconfig.me 2>/dev/null \
    || hostname -I 2>/dev/null | awk '{print $1}' \
    || echo ""
}

validator_install_deps() {
  local need_apt=0
  for cmd in python3 jq curl; do
    command -v "$cmd" >/dev/null 2>&1 || need_apt=1
  done
  if [[ "$need_apt" == "1" ]] && command -v apt-get >/dev/null 2>&1; then
    echo "==> Installing system dependencies (jq, curl, python3)..."
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      jq curl python3 ca-certificates >/dev/null 2>&1 \
      || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        jq curl python3 ca-certificates
  fi
  if [[ "${SUDO_BUILD_FROM_SOURCE:-0}" == "1" ]]; then
    for cmd in git gcc make; do
      command -v "$cmd" >/dev/null 2>&1 || need_apt=1
    done
    if [[ "$need_apt" == "1" ]] && command -v apt-get >/dev/null 2>&1; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        build-essential make git >/dev/null 2>&1 || true
    fi
    if ! command -v go >/dev/null 2>&1; then
      if [[ ! -x /usr/local/go/bin/go ]]; then
        echo "==> Installing Go 1.22 (source build mode)..."
        curl -fsSL https://go.dev/dl/go1.22.7.linux-amd64.tar.gz | sudo tar -C /usr/local -xz
      fi
      export PATH="$PATH:/usr/local/go/bin"
    fi
  fi
}

validator_build_sudod() {
  local chain_root="$1"
  local binary="${2:-$chain_root/build/sudod}"
  echo "==> Building sudod from $chain_root (first run may take 5-15 minutes)..."
  mkdir -p "$(dirname "$binary")"
  export PATH="${PATH}:/usr/local/go/bin"
  export CGO_ENABLED=1
  # Must build inside the Go module directory (not monorepo root).
  (cd "$chain_root" && go build -o "$binary" ./cmd/sudod)
  [[ -x "$binary" ]] || return 1
  echo "==> Build OK: $binary"
}

validator_get_balance_bash() {
  local binary="$1"
  local address="$2"
  local node
  node="$(validator_rpc_to_node "$PUBLIC_RPC")"
  local out
  if out="$("$binary" query bank balances "$address" --node "$node" -o json 2>/dev/null)"; then
    echo "$out" | jq -r '[.balances[] | select(.denom=="bash") | .amount][0] // "0"'
    return 0
  fi
  # REST fallback (LCD)
  local lcd="${PUBLIC_LCD:-}"
  if [[ -z "$lcd" && "$PUBLIC_RPC" == https://rpc.sudoscan.io ]]; then
    lcd="https://lcd.sudoscan.io"
  fi
  if [[ -n "$lcd" ]]; then
    curl -sf "${lcd}/cosmos/bank/v1beta1/balances/${address}" 2>/dev/null \
      | jq -r '[.balances[] | select(.denom=="bash") | .amount][0] // "0"' \
      && return 0
  fi
  echo "0"
  return 1
}

validator_wait_for_balance() {
  local binary="$1"
  local address="$2"
  local min_bash="$3"
  local interval="${4:-15}"
  echo "==> Waiting for >= $(python3 -c "print(${min_bash}/10**9)") SUDO on $address ..."
  echo "    Send SUDO to this address. Checking every ${interval}s (Ctrl+C to stop)."
  while true; do
    local bal
    bal="$(validator_get_balance_bash "$binary" "$address" || echo 0)"
    local sudo_amt
    sudo_amt="$(python3 -c "print(round(int('${bal:-0}')/10**9, 9))")"
    echo "    Balance: ${sudo_amt} SUDO"
    if python3 -c "exit(0 if int('${bal:-0}') >= int('${min_bash}') else 1)"; then
      echo "==> Balance OK (${sudo_amt} SUDO)"
      return 0
    fi
    sleep "$interval"
  done
}

validator_configure_node() {
  local config="$1"
  local app="$2"
  local peer="$3"
  local external_ip="${4:-}"

  sed -i 's/^timeout_commit = .*/timeout_commit = "3600ms"/' "$config"
  sed -i 's/^laddr = "tcp:\/\/127.0.0.1:26657"/laddr = "tcp:\/\/0.0.0.0:26657"/' "$config"
  # Use persistent_peers ONLY — do not set seeds to the same node (causes PEX disconnect loop)
  sed -i 's/^seeds = .*/seeds = ""/' "$config"
  sed -i 's/^persistent_peers = .*/persistent_peers = "'"$peer"'"/' "$config"
  sed -i 's/^pex = true/pex = false/' "$config"
  if [[ -n "$external_ip" ]]; then
    sed -i 's/^external_address = .*/external_address = "'"$external_ip"':26656"/' "$config"
  fi
  sed -i 's/^minimum-gas-prices = .*/minimum-gas-prices = "0.001bash"/' "$app"
}

validator_find_node_pid() {
  local home="$1"
  local pid=""
  if [[ -f "$home/node.pid" ]]; then
    pid="$(cat "$home/node.pid" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "$pid"
      return 0
    fi
  fi
  # Also detect nodes started outside join-validator (e.g. rsync deploy scripts).
  pid="$(pgrep -f "start --home ${home}" 2>/dev/null | head -1 || true)"
  if [[ -n "$pid" ]]; then
    echo "$pid"
  fi
  return 0
}

validator_node_running() {
  local home="$1"
  local pid
  pid="$(validator_find_node_pid "$home" || true)"
  [[ -n "$pid" ]]
}

validator_stop_node() {
  local home="$1"
  local pid
  pid="$(validator_find_node_pid "$home" || true)"
  if [[ -n "$pid" ]]; then
    echo "==> Stopping existing node (pid $pid)..."
    kill "$pid" 2>/dev/null || true
    local i
    for i in $(seq 1 15); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$home/node.pid"
}

validator_start_node_bg() {
  local binary="$1"
  local home="$2"
  local pid
  pid="$(validator_find_node_pid "$home" || true)"
  if [[ -n "$pid" ]]; then
    echo "$pid" >"$home/node.pid"
    echo "==> Node already running (pid $pid)"
    return 0
  fi
  echo "==> Starting node (first RPC may take 1-3 min after chain data copy)..."
  nohup "$binary" start --home "$home" >>"$home/node.log" 2>&1 &
  echo $! >"$home/node.pid"
  sleep 5
}

validator_wait_for_sync() {
  local rpc_port="${1:-26657}"
  local max_wait="${2:-3600}"
  echo "==> Waiting for node sync (max ${max_wait}s)..."
  local elapsed=0
  local not_ready=0
  while [[ "$elapsed" -lt "$max_wait" ]]; do
    if curl -sf "http://127.0.0.1:${rpc_port}/status" >/tmp/sudo-sync-status.json 2>/dev/null; then
      local catching_up height
      catching_up="$(jq -r '.result.sync_info.catching_up' /tmp/sudo-sync-status.json)"
      height="$(jq -r '.result.sync_info.latest_block_height' /tmp/sudo-sync-status.json)"
      echo "    height=$height catching_up=$catching_up"
      if [[ "$catching_up" == "false" && "$height" != "0" ]]; then
        echo "==> Node synced at height $height"
        return 0
      fi
    else
      not_ready=$((not_ready + 1))
      if (( not_ready % 3 == 1 )); then
        echo "    RPC not ready yet... (${elapsed}s elapsed — normal up to ~180s after data copy)"
      fi
      # If node died during startup, surface the error instead of waiting forever.
      if [[ -f "${VALIDATOR_HOME:-/opt/sudo-validator}/node.log" ]]; then
        if grep -q "panic:" "${VALIDATOR_HOME:-/opt/sudo-validator}/node.log" 2>/dev/null; then
          echo "ERROR: Node crashed — last log lines:"
          tail -20 "${VALIDATOR_HOME:-/opt/sudo-validator}/node.log" >&2
          return 1
        fi
      fi
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo "WARN: Sync wait timed out — continuing anyway (create-validator may fail if too far behind)"
  return 0
}

validator_is_registered() {
  local binary="$1"
  local home="$2"
  local valoper
  valoper="$("$binary" keys show validator --bech val -a --home "$home" --keyring-backend "${KEYRING_BACKEND:-file}" 2>/dev/null)" || return 1
  local node
  node="$(validator_tx_node)"
  "$binary" query staking validator "$valoper" --node "$node" -o json 2>/dev/null \
    | jq -e '.validator.status == "BOND_STATUS_BONDED" or .validator.status == "BOND_STATUS_UNBONDING"' >/dev/null
}

validator_register() {
  local binary="$1"
  local home="$2"
  local moniker="$3"
  local stake_bash
  stake_bash="$(validator_stake_bash)"
  local pubkey
  pubkey="$("$binary" tendermint show-validator --home "$home")"

  local validator_json="$home/validator.json"
  cat >"$validator_json" <<EOF
{
  "pubkey": $pubkey,
  "amount": "${stake_bash}bash",
  "moniker": "$moniker",
  "identity": "",
  "website": "",
  "security": "",
  "details": "SUDO auto-validator",
  "commission-rate": "0.10",
  "commission-max-rate": "0.20",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "${stake_bash}"
}
EOF

  echo "==> Submitting create-validator (${STAKE_SUDO} SUDO stake)..."
  local tx_node
  tx_node="$(validator_tx_node)"
  echo "    Broadcasting tx via: $tx_node"
  "$binary" tx staking create-validator "$validator_json" \
    --from validator \
    --chain-id "$CHAIN_ID" \
    --home "$home" \
    --node "$tx_node" \
    --keyring-backend "${KEYRING_BACKEND:-file}" \
    --gas 300000 \
    --fees 500bash \
    -y -b sync
}

validator_install_systemd() {
  local binary="$1"
  local home="$2"
  local service="/etc/systemd/system/sudo-validator.service"
  echo "==> Installing systemd service..."
  sudo tee "$service" >/dev/null <<EOF
[Unit]
Description=SUDO Validator (sudo99)
After=network-online.target

[Service]
Type=simple
User=${SUDO_USER:-root}
ExecStart=${binary} start --home ${home}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable sudo-validator
  if validator_node_running "$home"; then
    kill "$(cat "$home/node.pid")" 2>/dev/null || true
    sleep 2
  fi
  sudo systemctl restart sudo-validator
  echo "==> systemd: sudo-validator enabled + started"
}

validator_print_success() {
  local binary="$1"
  local home="$2"
  local wallet valoper node_id
  wallet="$("$binary" keys show validator -a --home "$home" --keyring-backend "${KEYRING_BACKEND:-file}")"
  valoper="$("$binary" keys show validator --bech val -a --home "$home" --keyring-backend "${KEYRING_BACKEND:-file}")"
  node_id="$("$binary" tendermint show-node-id --home "$home")"
  cat <<EOF

╔══════════════════════════════════════════════════════════════╗
║           SUDO VALIDATOR ACTIVE                              ║
╠══════════════════════════════════════════════════════════════╣
║  Wallet:    $wallet
║  Valoper:   $valoper
║  Node ID:   $node_id
║  Stake:     ${STAKE_SUDO} SUDO
║  Explorer:  https://sudoscan.io/validators
╚══════════════════════════════════════════════════════════════╝

Your validator will appear in block production when selected.
Gas fees from transactions are distributed to validators automatically.

EOF
}
