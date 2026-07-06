# SUDO Validator — New Server Deployment

> **Easiest way:** run `./join-validator.sh` from the repo root after `git clone`.
> Everything is automatic once your wallet has **1000 SUDO**.

## One-command join (recommended)

```bash
git clone https://github.com/Sudomessenger/Validator.git
cd Validator
./join-validator.sh
```

1. Script shows your wallet address
2. Send **≥ 1000 SUDO** to that address
3. Script waits, syncs, registers validator, starts node — **no manual steps**

Existing Keplr/Leap wallet:

```bash
./join-validator.sh --mnemonic "your seed phrase words here"
```

---

## Manual deployment (advanced)

## Overview

| Step | What |
|------|------|
| 1 | Install Go + build `sudod` |
| 2 | Init node + copy `genesis.json` from existing network |
| 3 | Connect to seed node (P2P) and sync |
| 4 | Create wallet key + fund with **1000 SUDO** |
| 5 | Submit `create-validator` tx |
| 6 | Run node 24/7 (systemd / pm2) |

**Validator earns tx gas fees only** (not mining rewards). Blocks show your **consensus address** (hex) under "Validated By" on [sudoscan.io](https://sudoscan.io).

---

## Server requirements

| Resource | Minimum |
|----------|---------|
| OS | Ubuntu 22.04+ / Debian 12+ |
| CPU | 2 vCPU |
| RAM | 4 GB |
| Disk | 80 GB SSD |
| Ports open (inbound) | **26656** (P2P, required) |
| Ports open (optional) | 26657 RPC, 1317 REST |

---

## Network info (current seed node)

Update these if your primary node IP changes.

| Setting | Value |
|---------|-------|
| Chain ID | `sudo99` |
| Bond denom | `bash` (display: SUDO, 9 decimals) |
| 1000 SUDO | `1000000000000bash` |
| Min gas price | `0.001bash` |
| Block time | ~3.6s (`timeout_commit = 3600ms`) |
| Seed node ID | `6eafed75e8db7b0eed2f608b211afde9f71de184` |
| Seed P2P | `6eafed75e8db7b0eed2f608b211afde9f71de184@<SEED_IP>:26656` |

**Important:** The seed/primary server must allow **inbound TCP 26656** from your new validator IP.

---

## Quick deploy (automated script)

On the **new server**:

```bash
# 1. Clone repo (or copy sudod binary + genesis)
git clone https://github.com/Sudomessenger/Validator.git
cd Validator

# 2. Set environment
export SEED_IP="<PRIMARY_NODE_PUBLIC_IP>"   # e.g. 170.64.178.165
export MONIKER="my-validator"
export STAKE_SUDO=1000                       # self-delegation in SUDO
export VALIDATOR_HOME=/opt/sudo-validator

# 3. Run setup (builds binary, inits node, configures peers)
chmod +x scripts/deploy-validator.sh
./scripts/deploy-validator.sh setup

# 4. Start sync
./scripts/deploy-validator.sh start

# 5. Wait until synced (catching_up = false)
./scripts/deploy-validator.sh status
```

After sync + wallet funded:

```bash
# Fund wallet first (see "Fund wallet" below), then:
./scripts/deploy-validator.sh register
```

---

## Manual step-by-step

### 1. Install dependencies

```bash
sudo apt update
sudo apt install -y build-essential git jq curl

# Go 1.22+
curl -fsSL https://go.dev/dl/go1.22.7.linux-amd64.tar.gz | sudo tar -C /usr/local -xz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc
```

### 2. Build sudod

```bash
git clone https://github.com/Sudomessenger/Validator.git
cd Validator
make build
# Binary: ./build/sudod
```

### 3. Init node

```bash
export HOME=/opt/sudo-validator
export CHAIN_ID=sudo99

./build/sudod init "$MONIKER" --chain-id $CHAIN_ID --home $HOME
```

### 4. Copy genesis from seed node

```bash
scp root@<SEED_IP>:/tmp/sudo-localnet/config/genesis.json $HOME/config/genesis.json
./build/sudod genesis validate-genesis --home $HOME
```

### 5. Configure P2P (connect to network)

Edit `$HOME/config/config.toml`:

```toml
[consensus]
timeout_commit = "3600ms"

[p2p]
laddr = "tcp://0.0.0.0:26656"
external_address = "<YOUR_NEW_SERVER_PUBLIC_IP>:26656"
seeds = ""
persistent_peers = "6eafed75e8db7b0eed2f608b211afde9f71de184@<SEED_IP>:26656"
```

Edit `$HOME/config/app.toml`:

```toml
minimum-gas-prices = "0.001bash"
```

### 6. Create validator wallet key

```bash
./build/sudod keys add validator --home $HOME --keyring-backend file
./build/sudod keys show validator -a --home $HOME --keyring-backend file
# Save mnemonic securely!
```

### 7. Start node and sync

```bash
./build/sudod start --home $HOME
```

Check sync:

```bash
curl -s localhost:26657/status | jq '.result.sync_info'
# catching_up must be false before create-validator
```

### 8. Fund wallet

Send **≥ 1000 SUDO** (+ ~1 SUDO for fees) to your new validator wallet address from any funded account:

```bash
# From seed node (example — use your funded key):
./build/sudod tx bank send <from-key> <NEW_VALIDATOR_WALLET> 1001000000000bash \
  --chain-id sudo99 \
  --home /tmp/sudo-localnet \
  --keyring-backend test \
  --gas 200000 --fees 500bash -y
```

### 9. Register validator on-chain

```bash
PUBKEY=$(./build/sudod tendermint show-validator --home $HOME)
STAKE_BASH=1000000000000   # 1000 SUDO

cat > /tmp/validator.json <<EOF
{
  "pubkey": $PUBKEY,
  "amount": "${STAKE_BASH}bash",
  "moniker": "$MONIKER",
  "identity": "",
  "website": "",
  "security": "",
  "details": "SUDO validator",
  "commission-rate": "0.10",
  "commission-max-rate": "0.20",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "${STAKE_BASH}"
}
EOF

./build/sudod tx staking create-validator /tmp/validator.json \
  --from validator \
  --chain-id sudo99 \
  --home $HOME \
  --keyring-backend file \
  --gas 300000 \
  --fees 500bash \
  -y
```

### 10. Verify

```bash
./build/sudod query staking validators --node tcp://localhost:26657
./build/sudod keys show validator --bech val -a --home $HOME --keyring-backend file
```

Check [sudoscan.io/validators](https://sudoscan.io/validators) — your moniker should appear. When your turn comes, "Validated By" on home page shows your consensus address.

---

## Run as systemd service

```bash
sudo tee /etc/systemd/system/sudo-validator.service <<EOF
[Unit]
Description=SUDO Validator Node (sudo99)
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/opt/sudo-validator-deploy/build/sudod start --home /opt/sudo-validator
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable sudo-validator
sudo systemctl start sudo-validator
sudo journalctl -u sudo-validator -f
```

---

## Seed node checklist (primary server)

On the **existing** node operator:

1. Open firewall: `sudo ufw allow 26656/tcp`
2. Confirm P2P listens on `0.0.0.0:26656` in `config.toml`
3. Optionally set `external_address = "<SEED_IP>:26656"`
4. Share `genesis.json` + node ID with new validator operator

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `connection refused` on sync | Check seed IP, port 26656 open, `persistent_peers` correct |
| `catching_up: true` forever | Wait; check seed node is running; verify genesis hash matches |
| `insufficient funds` | Fund wallet with 1000 SUDO + fees |
| `validator already exists` | Consensus key already registered; use new node or edit moniker only |
| Not producing blocks | Must be in top 99 bonded validators; node must be synced and `priv_validator` running |

---

## Token math

| SUDO | bash (base units) |
|------|-------------------|
| 1 | `1000000000` |
| 1000 | `1000000000000` |
| Tx fee (~200k gas) | `~200bash` (0.0000002 SUDO) |
