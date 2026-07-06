# Validator Join — Test Guide

Test with your existing wallet (1000+ SUDO).

## Git repo

```
https://github.com/Sudomessenger/Validator.git
```

## Option A — Private key (app / Keplr export)

```bash
./join-validator.sh --private-key "YOUR_HEX_PRIVATE_KEY_WITHOUT_0x" --moniker my-validator
```

Or via stdin (safer):

```bash
echo "YOUR_HEX_PRIVATE_KEY" | ./join-validator.sh --private-key-stdin --moniker my-validator
```

## Option B — Mnemonic (seed phrase)

```bash
./join-validator.sh --mnemonic "your twelve or twenty four words here" --moniker my-test-validator
```

## Option C — App-style remote deploy (server IP + password + mnemonic)

From your laptop:

```bash
sudo apt install -y sshpass   # once

git clone https://github.com/Sudomessenger/Validator.git
cd Validator

./scripts/deploy-remote-validator.sh \
  --server-ip YOUR_SERVER_IP \
  --user root \
  --password 'YOUR_SSH_PASSWORD' \
  --mnemonic "your mnemonic words here" \
  --moniker my-validator
```

This SSHs to the server, clones repo, runs join-validator automatically.

## Option C — Mnemonic via stdin (safer — not in shell history)

```bash
echo "word1 word2 ... word24" | ./join-validator.sh --mnemonic-stdin --moniker my-validator
```

## Verify

```bash
# On validator server
sudo systemctl status sudo-validator
curl -s localhost:26657/status | jq '.result.sync_info'

# Explorer
# https://sudoscan.io/validators
```

## Requirements

| Item | Value |
|------|-------|
| Wallet balance | >= 1000 SUDO |
| Server port | 26656 open (inbound) |
| Seed node | port 26656 open on primary (170.64.178.165) |

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Insufficient balance` | Wait or send more SUDO to wallet |
| `connection refused` sync | Open port 26656 on seed + validator server |
| `validator already exists` | Wallet already registered — use new server key or unbond first |
| Build slow | First run compiles sudod (~5-10 min) |

## Future app flow (same backend)

```
App UI:
  [ Mnemonic input ]
  [ Server IP      ]
  [ SSH Password   ]
  [ Deploy button  ]
        ↓
  calls deploy-remote-validator.sh API
        ↓
  Validator active on sudoscan.io
```
