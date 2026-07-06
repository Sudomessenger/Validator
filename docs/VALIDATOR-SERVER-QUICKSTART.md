# Validator Server — Production Deploy (reset VPS)

Fresh Ubuntu VPS par **sirf ye steps** — kuch manual nahi.

## Step 1 — Clone repo

```bash
git clone https://github.com/Sudomessenger/Validator.git /opt/sudo-validator-deploy
cd /opt/sudo-validator-deploy
```

## Step 2 — Credentials set karo (ek baar)

```bash
cp config/validator-deploy.env.example config/validator-deploy.env
nano config/validator-deploy.env
```

Fill in:
```bash
VALIDATOR_PRIVATE_KEY=0xYOUR_KEY
MONIKER=my-validator
```

## Step 3 — Install (auto: deps + build + genesis + sync + systemd + unjail)

**Terminal band na ho iske liye `--background` use karo (recommended):**

```bash
VALIDATOR_PRIVATE_KEY=0xYOUR_KEY MONIKER=my-validator bash install-validator.sh --background
tail -f /var/log/sudo-validator-install.log
```

Foreground (terminal open rakho):
```bash
bash install-validator.sh
```

Status check:
```bash
bash scripts/validator-install-status.sh
```

**Bas.** Script khud karegi:
- apt packages + Go install
- `sudod` build
- Live genesis seed se fetch
- Firewall ports 26656/26657
- Seed se block sync
- systemd service
- Jailed ho to unjail

---

## One-liner (env file ke bina)

```bash
git clone https://github.com/Sudomessenger/Validator.git /opt/sudo-validator-deploy
cd /opt/sudo-validator-deploy
VALIDATOR_PRIVATE_KEY=0xYOUR_KEY MONIKER=my-validator bash install-validator.sh
```

---

## VPS reset se pehle (seed par — consensus keys backup)

Validator ke purane server par keys backup karo **reset se pehle**:

```bash
# Seed server par:
SSHPASS='vps-password' bash scripts/backup-vps-validator-config.sh
```

Fresh VPS par redeploy script seed se backup auto-fetch karegi (SSH allow ho to).

---

## Updates (code pull + resync)

```bash
cd /opt/sudo-validator-deploy
bash scripts/validator-pull-and-start.sh
```

---

## Verify

```bash
systemctl status sudo-validator
curl -s localhost:26657/status | jq .result.sync_info
journalctl -u sudo-validator -f
```

Explorer: https://sudoscan.io/validators

---

## Network defaults

`config/validator-network.env`

| Key | Value |
|-----|-------|
| SEED_IP | 170.64.178.165 |
| SEED_NODE_ID | 6eafed75e8db7b0eed2f608b211afde9f71de184 |
| CHAIN_ID | sudo99 |
