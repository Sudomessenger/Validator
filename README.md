# SUDO Validator Deployment

Production-ready tooling to deploy and operate a **SUDO network validator** (`sudo99`). This repository contains only validator deployment scripts, configuration templates, and documentation — no application, explorer, wallet, or smart contract code.

Join the SUDO proof-of-stake network, sync from the seed node, register your validator with **1000 SUDO** self-delegation, and run a 24/7 node with systemd.

**Explorer:** [sudoscan.io/validators](https://sudoscan.io/validators)

---

## Project Overview

| Item | Value |
|------|-------|
| Chain ID | `sudo99` |
| Native denom | `bash` (display: **SUDO**, 9 decimals) |
| Minimum stake | **1000 SUDO** (`1000000000000bash`) |
| Address prefix | `99` |
| Block time | ~3.6s |
| Seed node ID | `6eafed75e8db7b0eed2f608b211afde9f71de184` |
| Seed P2P | `6eafed75e8db7b0eed2f608b211afde9f71de184@170.64.178.165:26656` |
| Public RPC | `https://rpc.sudoscan.io` |

Validators earn **transaction gas fees** (not mining rewards). When your validator is selected to propose a block, it appears under "Validated By" on the explorer.

### What this repo does

1. Installs system dependencies (jq, curl, python3)
2. Downloads pre-built `sudod` from GitHub Release (**no network repo**)
3. Fetches live genesis from the network
4. Configures P2P peers and opens firewall ports
5. Creates or imports your validator wallet
6. Waits for **1000 SUDO** funding, submits `create-validator`, syncs blocks
7. Installs a **systemd** service and unjails if needed

### Repository layout

```
Validator/
├── install-validator.sh      # One-command production install (recommended)
├── join-validator.sh           # Wrapper → scripts/join-validator.sh
├── config/
│   ├── validator-network.env       # Network defaults (seed, RPC, stake)
│   ├── validator-deploy.env.example # Wallet credentials template
│   └── genesis.sudo99.json         # Bundled genesis fallback
├── scripts/
│   ├── bootstrap-validator.sh      # Called by install-validator.sh
│   ├── join-validator.sh           # Full automated join flow
│   ├── deploy-validator.sh         # Manual step-by-step deploy
│   ├── deploy-remote-validator.sh  # SSH deploy to remote VPS
│   ├── validator-install-status.sh # Check install / node status
│   ├── unjail-validator.sh         # Unjail after downtime
│   ├── start-vps-validator-now.sh  # Resync existing validator
│   ├── validator-pull-and-start.sh # Git pull + resync
│   └── lib/validator-common.sh     # Shared helpers
└── docs/                           # Detailed guides
```

---

## Prerequisites

### Server

| Resource | Minimum |
|----------|---------|
| OS | Ubuntu 22.04+ / Debian 12+ |
| CPU | 2 vCPU |
| RAM | 4 GB |
| Disk | 80 GB SSD |
| Inbound ports | **26656** TCP (P2P, required) |
| Optional ports | 26657 (RPC), 1317 (REST) |

### Wallet

- A funded wallet with **≥ 1000 SUDO** (+ small fee buffer), **or**
- Let the script generate a new wallet and fund the displayed address

### Credentials (choose one)

- **Private key** — 64 hex characters (with or without `0x` prefix)
- **Mnemonic** — 12 or 24 word seed phrase

> **Security:** Never commit `config/validator-deploy.env`. Use `chmod 600` on credential files.

---

## Installation

### 1. Clone this repository

```bash
git clone https://github.com/Sudomessenger/Validator.git
cd Validator
chmod +x install-validator.sh join-validator.sh scripts/*.sh
```

### 2. (Optional) Configure credentials file

```bash
cp config/validator-deploy.env.example config/validator-deploy.env
chmod 600 config/validator-deploy.env
nano config/validator-deploy.env
```

Example `config/validator-deploy.env`:

```bash
VALIDATOR_PRIVATE_KEY=0xYOUR_64_CHAR_HEX_KEY
MONIKER=my-validator
VALIDATOR_HOME=/opt/sudo-validator
```

### 3. Run the installer

**Background mode (recommended for VPS — safe to close SSH):**

```bash
VALIDATOR_PRIVATE_KEY=0xYOUR_KEY MONIKER=my-validator bash install-validator.sh --background
tail -f /var/log/sudo-validator-install.log
```

**Foreground mode:**

```bash
bash install-validator.sh
```

**Check status:**

```bash
bash scripts/validator-install-status.sh
# or
bash install-validator.sh --status
```

First run downloads pre-built `sudod` from GitHub Release (~90 MB, 1–3 min). **No `network` repo needed.**

---

## Configuration

### Network settings — `config/validator-network.env`

| Variable | Default | Description |
|----------|---------|-------------|
| `CHAIN_ID` | `sudo99` | Chain identifier |
| `SEED_NODE_ID` | `6eafed75e8db7b0eed2f608b211afde9f71de184` | Seed node CometBFT ID |
| `SEED_IP` | `170.64.178.165` | Seed node public IP |
| `SEED_P2P_PORT` | `26656` | P2P port |
| `PUBLIC_RPC` | `https://rpc.sudoscan.io` | Public RPC endpoint |
| `PUBLIC_TX_NODE` | `tcp://170.64.178.165:26657` | Tx broadcast node |
| `USE_STATE_SYNC` | `1` | Fast sync via state snapshots (~5–15 min) |
| `STATE_SYNC_TRUST_OFFSET` | `2000` | Blocks behind tip for trust height |
| `STAKE_SUDO` | `1000` | Self-delegation amount |
| `FEE_BUFFER_SUDO` | `1` | Extra SUDO reserved for fees |

Override any value via environment variables without editing files:

```bash
export SEED_IP=1.2.3.4
export STAKE_SUDO=1000
export MONIKER=my-validator
```

### Advanced environment variables

| Variable | Description |
|----------|-------------|
| `VALIDATOR_HOME` | Node data directory (default: `/opt/sudo-validator`) |
| `SUDOD_DOWNLOAD_URL` | Pre-built binary URL (default: GitHub Release) |
| `SUDOD_BIN` | Path to existing sudod (skip download) |
| `EXTERNAL_IP` | Force advertised P2P address |
| `INSTALL_SYSTEMD` | `1` (default) or `0` to skip systemd |
| `WAIT_FOR_FUNDS` | `1` (default) — wait for wallet funding |
| `USE_STATE_SYNC` | `1` (default) — state sync; `0` = slow block sync from genesis |

### State sync (fast deploy — default)

New validators use **state sync** (~5–15 min) instead of block sync (30–90+ min, grows with chain size).

**One-time on seed server** (`170.64.178.165`):

```bash
git clone https://github.com/Sudomessenger/Validator.git /opt/validator-worker
cd /opt/validator-worker && git pull origin main
bash scripts/enable-seed-snapshots.sh
```

After ~1000 blocks, seed serves snapshots. All new deploys auto-use state sync.

Fallback: if RPC/trust fetch fails, deploy script falls back to block sync automatically.

---

## Deployment Instructions

### Option A — One-command install (recommended)

```bash
git clone https://github.com/Sudomessenger/Validator.git
cd Validator
VALIDATOR_PRIVATE_KEY=0x... MONIKER=my-validator bash install-validator.sh --background
```

Flow: fund wallet → sync → register → systemd → unjail.

### Option B — Join with existing wallet

```bash
./join-validator.sh --mnemonic "word1 word2 ... word24" --moniker my-validator
```

Or with private key (stdin avoids shell history):

```bash
echo "YOUR_HEX_PRIVATE_KEY" | ./join-validator.sh --private-key-stdin --moniker my-validator
```

### Option C — Manual step-by-step

```bash
export SEED_IP=170.64.178.165
export MONIKER=my-validator
./scripts/deploy-validator.sh setup
./scripts/deploy-validator.sh start
# Fund wallet, then:
./scripts/deploy-validator.sh register
./scripts/deploy-validator.sh status
```

### Option D — Remote deploy from your laptop

Requires `sshpass` on your local machine:

```bash
sudo apt install -y sshpass

./scripts/deploy-remote-validator.sh \
  --server-ip YOUR_SERVER_IP \
  --user root \
  --password 'YOUR_SSH_PASSWORD' \
  --mnemonic "your mnemonic words here" \
  --moniker my-validator
```

### Option E — Resync after VPS reset (keep keys)

If you backed up consensus keys before reset:

```bash
export VALIDATOR_CONFIG_BACKUP=/path/to/priv_validator_backup.tar.gz
bash install-validator.sh
```

Or resync an existing node:

```bash
bash scripts/start-vps-validator-now.sh
```

---

## Usage Examples

### New wallet (script generates address)

```bash
./join-validator.sh
# Send ≥ 1000 SUDO to the displayed address
# Script waits, registers, and starts automatically
```

### Verify node is running

```bash
sudo systemctl status sudo-validator
curl -s localhost:26657/status | jq '.result.sync_info'
bash scripts/validator-install-status.sh
```

### Unjail after downtime

```bash
bash scripts/unjail-validator.sh
```

### Update scripts and resync

```bash
bash scripts/validator-pull-and-start.sh
```

### Skip balance wait (wallet already funded)

```bash
./join-validator.sh --private-key 0xYOUR_KEY --no-wait
```

### Use pre-built binary (skip Go build)

```bash
export SUDOD_BIN=/usr/local/bin/sudod
bash install-validator.sh
```

---

## Troubleshooting

| Issue | Action |
|-------|--------|
| Install log | `tail -f /var/log/sudo-validator-install.log` |
| Node log | `tail -f /opt/sudo-validator/node.log` |
| systemd logs | `journalctl -u sudo-validator -f` |
| RPC not responding | Wait 1–3 min after start; check firewall on port 26656 |
| Jailed validator | `bash scripts/unjail-validator.sh` |
| Sync stuck | `bash scripts/start-vps-validator-now.sh` |

See [docs/VALIDATOR_DEPLOY.md](docs/VALIDATOR_DEPLOY.md) for the full deployment guide.

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/VALIDATOR_DEPLOY.md](docs/VALIDATOR_DEPLOY.md) | Complete deployment guide |
| [docs/VALIDATOR-SERVER-QUICKSTART.md](docs/VALIDATOR-SERVER-QUICKSTART.md) | VPS quickstart |
| [docs/VALIDATOR_TEST.md](docs/VALIDATOR_TEST.md) | Testing with existing wallet |

---

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [Sudomessenger/network](https://github.com/Sudomessenger/network) | SUDO chain source (`sudod` binary) |
| [sudoscan.io](https://sudoscan.io) | Block explorer |

This repository is **standalone** — it does **not** clone `Sudomessenger/network`.  
The `sudod` node binary is downloaded from [GitHub Releases](https://github.com/Sudomessenger/Validator/releases).

---

## License

Copyright 2026 Sudomessenger

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.
