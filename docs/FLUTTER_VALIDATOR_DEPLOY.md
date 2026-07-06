# Flutter App — Validator Deploy Integration

**File:** `FLUTTER_VALIDATOR_DEPLOY.md`  
**Audience:** Flutter + Backend developer  
**Validator repo:** https://github.com/Sudomessenger/Validator (public, standalone)  
**Explorer:** https://sudoscan.io/validators

---

## Integration checklist (Flutter team)

| # | Task | Owner |
|---|------|-------|
| 1 | Wallet screen — address + balance >= **1001 SUDO** | Flutter |
| 2 | Deploy form — **Server IP**, **SSH Password**, **Moniker** | Flutter |
| 3 | `POST /api/validator/deploy` call (mnemonic secure storage se) | Flutter |
| 4 | Progress screen — poll `GET /api/validator/deploy/{jobId}` | Flutter |
| 5 | My Validator — LCD/explorer se bonded status | Flutter |
| 6 | Backend worker — clone Validator + run `deploy-remote-validator.sh` | Backend |
| 7 | Worker par `git pull` latest Validator repo | Backend |

**User app me 3 fields:** Server IP · SSH Password · Validator Name  
**Network repo use nahi hota** — sirf public `Validator` repo + sudod download.

---

## Repos — sirf Validator chahiye (network repo nahi)

| Repo | Zarurat? | Kya hai |
|------|----------|---------|
| **[Sudomessenger/Validator](https://github.com/Sudomessenger/Validator)** | **Haan — public** | Deploy scripts + config |
| ~~Sudomessenger/network~~ | **Nahi** | Purana chain source — ab use nahi hota |

**Validator repo standalone hai.** `sudod` binary **GitHub Release** se download hoti hai — koi private repo clone nahi.

```bash
git clone https://github.com/Sudomessenger/Validator.git /opt/validator-worker
cd /opt/validator-worker
# sudod auto-download: config/validator-network.env → SUDOD_DOWNLOAD_URL
```

**`GITHUB_TOKEN` ki zarurat nahi** — sirf public Validator repo + public sudod release.

---

## Main flow (yahi implement karna hai)

```
User App                          Backend API                         User ka VPS
────────                          ───────────                         ────────────
1. Wallet (app me pehle se)  →
2. Fund >= 1001 SUDO         →
3. Server IP daalo           →
4. SSH Password daalo        →
5. Moniker daalo             →
6. "Deploy" button           →   POST /api/validator/deploy    →   SSH login
                                 (IP + password + mnemonic)         git clone Validator
                                                                    join-validator.sh
7. Progress screen           ←   GET /api/validator/deploy/{id} ←   sudod sync + register
8. Active ✅                 ←   bonded status poll
```

**User sirf yeh 3 cheezein app me bharega (deploy ke liye):**

| Field | Required | Example |
|-------|----------|---------|
| **Server IP** | ✅ | `147.93.153.13` |
| **SSH Password** | ✅ | VPS root password |
| **Validator Name (moniker)** | ✅ | `my-validator` |
| SSH User | Optional (default `root`) | `root` |

Wallet **mnemonic / private key** app ke secure storage se backend ko jayegi — user dubara type nahi karega.

---

## Network constants

```dart
class ValidatorConfig {
  static const chainId = 'sudo99';
  static const lcd = 'https://lcd.sudoscan.io';
  static const rpc = 'https://rpc.sudoscan.io';
  static const explorerApi = 'https://sudoscan.io';
  static const denom = 'bash'; // SUDO
  static const decimals = 9;
  static const minStakeSudo = 1000;
  static const minStakeBash = '1000000000000';
  static const feeBufferBash = '1000000000'; // +1 SUDO fees

  static BigInt get minRequiredBash =>
      BigInt.parse(minStakeBash) + BigInt.parse(feeBufferBash);
}
```

---

## App screens (step-by-step)

### Screen 1 — Requirements
- Minimum **1001 SUDO** in app wallet
- Ubuntu VPS (22.04+), 2 CPU, 4 GB RAM, 80 GB disk
- Port **26656** open (P2P)

### Screen 2 — Fund wallet
- Wallet address + QR
- Poll balance until >= 1001 SUDO

### Screen 3 — Server details ⭐ (MAIN)

```
┌─────────────────────────────────────┐
│  Deploy Validator on Your Server    │
├─────────────────────────────────────┤
│  Server IP *                        │
│  [ 147.93.153.13              ]     │
│                                     │
│  SSH Password *                     │
│  [ ••••••••••                 ]     │
│                                     │
│  SSH User (optional)                │
│  [ root                       ]     │
│                                     │
│  Validator Name *                   │
│  [ my-validator               ]     │
│                                     │
│  [        Deploy Now        ]       │
└─────────────────────────────────────┘
```

Validation:
- IP format valid
- Password not empty
- Balance >= 1001 SUDO
- Moniker 3–70 chars

### Screen 4 — Deploy progress
- `Connecting to server...`
- `Installing dependencies...`
- `Downloading sudod binary...`
- `Registering validator...`
- `Syncing blocks (30–90 min)...`
- `Active ✅`

### Screen 5 — My Validator
- Moniker, stake, status (bonded/jailed)
- Link: `https://sudoscan.io/validators`

---

## Backend API (Flutter team backend ko ye spec do)

### 1) Start deploy

```http
POST /api/validator/deploy
Content-Type: application/json
Authorization: Bearer <user_jwt>
```

**Request body:**

```json
{
  "serverIp": "147.93.153.13",
  "sshPassword": "user_vps_password",
  "sshUser": "root",
  "moniker": "my-validator",
  "walletAddress": "99ucr48vn2r595ttnu2454umlvkndcc8zeqqqqqq",
  "mnemonic": "word1 word2 word3 ... word24"
}
```

> Agar app private key use karti hai to `"privateKey": "0x64hex..."` bhejo, `mnemonic` mat bhejo.

**Success (202 Accepted):**

```json
{
  "ok": true,
  "jobId": "dep_7f3a9c2e",
  "message": "Deploy started on 147.93.153.13",
  "estimatedMinutes": 60
}
```

**Errors:**

| HTTP | Body | Reason |
|------|------|--------|
| 400 | `{ "ok": false, "error": "Insufficient balance" }` | Wallet < 1001 SUDO |
| 400 | `{ "ok": false, "error": "Invalid server IP" }` | Bad IP |
| 502 | `{ "ok": false, "error": "SSH connection failed" }` | Wrong IP/password |
| 409 | `{ "ok": false, "error": "Deploy already running" }` | Duplicate job |

---

### 2) Poll deploy status

```http
GET /api/validator/deploy/{jobId}
Authorization: Bearer <user_jwt>
```

**Response:**

```json
{
  "ok": true,
  "jobId": "dep_7f3a9c2e",
  "serverIp": "147.93.153.13",
  "status": "syncing",
  "steps": [
    { "id": "ssh_connect", "label": "Connected to server", "done": true },
    { "id": "clone_repo", "label": "Validator repo cloned", "done": true },
    { "id": "download_sudod", "label": "Node binary downloaded", "done": true },
    { "id": "create_validator", "label": "Validator registered on-chain", "done": true },
    { "id": "block_sync", "label": "Syncing blocks", "done": false },
    { "id": "systemd", "label": "Node running 24/7", "done": false }
  ],
  "valoperAddress": "99valoper1abc...",
  "moniker": "my-validator",
  "jailed": false,
  "explorerUrl": "https://sudoscan.io/validators"
}
```

**`status` values:**

| status | UI text |
|--------|---------|
| `queued` | Waiting to start... |
| `connecting` | Connecting to your server... |
| `installing` | Installing on VPS... |
| `registering` | Registering validator... |
| `syncing` | Syncing blocks (please wait)... |
| `active` | Validator active ✅ |
| `jailed` | Validator jailed — fixing... |
| `failed` | Deploy failed ❌ |

Poll har **15–30 sec** jab tak `active` ya `failed` na ho.

---

## Backend implementation (server-side)

### Step 0 — Worker install (public repo only)

```bash
git clone https://github.com/Sudomessenger/Validator.git /opt/validator-worker
cd /opt/validator-worker
sudo apt install -y sshpass   # one-time
git pull origin main          # updates ke liye
```

`sudod` binary automatically download hoti hai (`SUDOD_DOWNLOAD_URL` in `config/validator-network.env`).  
**Sudomessenger/network repo ki zarurat nahi.**

### Step 1 — User VPS par deploy

Backend worker ye script chalata hai:
```bash
cd /opt/validator-worker

./scripts/deploy-remote-validator.sh \
  --server-ip "$SERVER_IP" \
  --user "$SSH_USER" \
  --password "$SSH_PASSWORD" \
  --moniker "$MONIKER" \
  --mnemonic "$MNEMONIC"
```

Script automatically VPS par:
1. SSH login (IP + password)
2. `git clone` Validator repo
3. `join-validator.sh` — wallet import + node init + sync + `create-validator` + systemd

**Backend worker example (Node.js sketch):**

```javascript
const { execFile } = require('child_process');
const util = require('util');
const exec = util.promisify(execFile);

async function startDeploy({ serverIp, sshUser, sshPassword, moniker, mnemonic }) {
  await exec('/opt/validator-worker/scripts/deploy-remote-validator.sh', [
    '--server-ip', serverIp,
    '--user', sshUser || 'root',
    '--password', sshPassword,
    '--moniker', moniker,
    '--mnemonic', mnemonic,
  ], { timeout: 3_600_000 }); // 1 hour max
}
```

Deploy **async job** rakho (Redis queue / background worker) — HTTP request turant `jobId` return kare, script background me chale.

---

## Flutter — complete service file

`lib/services/validator_service.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ValidatorConfig {
  static const chainId = 'sudo99';
  static const lcd = 'https://lcd.sudoscan.io';
  static const explorerApi = 'https://sudoscan.io';
  static const denom = 'bash';
  static const minStakeBash = '1000000000000';
  static const feeBufferBash = '1000000000';

  static BigInt get minRequiredBash =>
      BigInt.parse(minStakeBash) + BigInt.parse(feeBufferBash);

  static String bashToSudo(String bash) {
    final v = BigInt.tryParse(bash) ?? BigInt.zero;
    return (v / BigInt.from(1000000000)).toString();
  }
}

class ValidatorService {
  ValidatorService({this.apiBase = 'https://api.yourapp.com'});

  final String apiBase;

  Future<BigInt> getBalance(String address) async {
    final res = await http.get(Uri.parse(
      '${ValidatorConfig.lcd}/cosmos/bank/v1beta1/balances/$address',
    ));
    if (res.statusCode != 200) return BigInt.zero;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    for (final b in (json['balances'] as List? ?? [])) {
      if (b['denom'] == ValidatorConfig.denom) {
        return BigInt.parse(b['amount'] as String);
      }
    }
    return BigInt.zero;
  }

  bool canDeploy(BigInt bash) => bash >= ValidatorConfig.minRequiredBash;

  Future<String> startDeploy({
    required String serverIp,
    required String sshPassword,
    required String moniker,
    required String walletAddress,
    required String mnemonic,
    String sshUser = 'root',
  }) async {
    final res = await http.post(
      Uri.parse('$apiBase/api/validator/deploy'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'serverIp': serverIp,
        'sshPassword': sshPassword,
        'sshUser': sshUser,
        'moniker': moniker,
        'walletAddress': walletAddress,
        'mnemonic': mnemonic,
      }),
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) throw Exception(json['error'] ?? 'Deploy failed');
    return json['jobId'] as String;
  }

  Future<Map<String, dynamic>> getDeployStatus(String jobId) async {
    final res = await http.get(Uri.parse('$apiBase/api/validator/deploy/$jobId'));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
```

---

## Flutter code — Deploy form (Server IP + Password)

`lib/screens/validator_deploy_screen.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ValidatorDeployScreen extends StatefulWidget {
  final String walletAddress;
  final Future<String?> Function() getMnemonic; // secure storage se

  const ValidatorDeployScreen({
    required this.walletAddress,
    required this.getMnemonic,
  });

  @override
  State<ValidatorDeployScreen> createState() => _ValidatorDeployScreenState();
}

class _ValidatorDeployScreenState extends State<ValidatorDeployScreen> {
  final _ipCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _userCtrl = TextEditingController(text: 'root');
  final _monikerCtrl = TextEditingController(text: 'my-validator');

  bool _loading = false;
  String? _error;
  String? _jobId;

  static const _apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://api.yourapp.com',
  );

  Future<void> _deploy() async {
    final ip = _ipCtrl.text.trim();
    final pass = _passCtrl.text;
    final moniker = _monikerCtrl.text.trim();

    if (ip.isEmpty || pass.isEmpty || moniker.isEmpty) {
      setState(() => _error = 'Server IP, password aur validator name zaroori hai');
      return;
    }

    final mnemonic = await widget.getMnemonic();
    if (mnemonic == null || mnemonic.isEmpty) {
      setState(() => _error = 'Wallet unlock karo — mnemonic chahiye');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final res = await http.post(
        Uri.parse('$_apiBase/api/validator/deploy'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'serverIp': ip,
          'sshPassword': pass,
          'sshUser': _userCtrl.text.trim().isEmpty ? 'root' : _userCtrl.text.trim(),
          'moniker': moniker,
          'walletAddress': widget.walletAddress,
          'mnemonic': mnemonic,
        }),
      );

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['ok'] != true) {
        throw Exception(json['error'] ?? 'Deploy failed');
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ValidatorDeployProgressScreen(
            jobId: json['jobId'] as String,
            serverIp: ip,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deploy on Your Server')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Apne VPS ka IP aur SSH password daalo. '
              'Validator usi server par install hoga.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ipCtrl,
              decoration: const InputDecoration(
                labelText: 'Server IP *',
                hintText: '147.93.153.13',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'SSH Password *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: 'SSH User (default: root)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _monikerCtrl,
              decoration: const InputDecoration(
                labelText: 'Validator Name *',
                hintText: 'my-validator',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const Spacer(),
            FilledButton(
              onPressed: _loading ? null : _deploy,
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Deploy Validator'),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## Flutter code — Progress poll

```dart
class ValidatorDeployProgressScreen extends StatefulWidget {
  final String jobId;
  final String serverIp;
  const ValidatorDeployProgressScreen({
    required this.jobId,
    required this.serverIp,
  });

  @override
  State<ValidatorDeployProgressScreen> createState() =>
      _ValidatorDeployProgressScreenState();
}

class _ValidatorDeployProgressScreenState
    extends State<ValidatorDeployProgressScreen> {
  Timer? _timer;
  Map<String, dynamic>? _status;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _poll());
  }

  Future<void> _poll() async {
    final res = await http.get(
      Uri.parse('$_apiBase/api/validator/deploy/${widget.jobId}'),
    );
    if (!mounted) return;
    setState(() => _status = jsonDecode(res.body) as Map<String, dynamic>);

    final s = _status?['status'] as String?;
    if (s == 'active' || s == 'failed') _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = (_status?['steps'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final status = _status?['status'] as String? ?? 'connecting';

    return Scaffold(
      appBar: AppBar(title: Text('Deploying on ${widget.serverIp}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Status: $status', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...steps.map((s) => ListTile(
                leading: Icon(
                  s['done'] == true ? Icons.check_circle : Icons.hourglass_empty,
                  color: s['done'] == true ? Colors.green : Colors.grey,
                ),
                title: Text(s['label'] as String? ?? ''),
              )),
          if (status == 'active')
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: FilledButton(
                onPressed: () => launchUrl(Uri.parse('https://sudoscan.io/validators')),
                child: const Text('View on Explorer'),
              ),
            ),
        ],
      ),
    );
  }
}
```

---

## Balance check (deploy se pehle)

```http
GET https://lcd.sudoscan.io/cosmos/bank/v1beta1/balances/{walletAddress}
```

Deploy button tab hi enable karo jab balance >= **1001 SUDO** (`1001000000000bash`).

```dart
Future<BigInt> getBashBalance(String address) async {
  final res = await http.get(Uri.parse(
    '${ValidatorConfig.lcd}/cosmos/bank/v1beta1/balances/$address',
  ));
  if (res.statusCode != 200) return BigInt.zero;
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  for (final b in (json['balances'] as List? ?? [])) {
    if (b['denom'] == 'bash') return BigInt.parse(b['amount'] as String);
  }
  return BigInt.zero;
}
```

---

## Validator active check (LCD)

Deploy ke baad bonded confirm karo:

```http
GET https://lcd.sudoscan.io/cosmos/staking/v1beta1/validators/{valoperAddress}
```

`validator.status == "BOND_STATUS_BONDED"` → active ✅  
`validator.jailed == true` → backend/VPS par unjail chahiye

---

## VPS requirements (user ko app me dikhao)

| Item | Value |
|------|-------|
| OS | Ubuntu 22.04+ |
| SSH | Port 22 open, root login + password |
| P2P | Port **26656** TCP inbound |
| RAM | 4 GB min |
| Disk | 80 GB SSD |

---

## Security rules

| Rule | Kyun |
|------|------|
| SSH password sirf **HTTPS POST** se backend ko bhejo | Sniffing se bachao |
| Mnemonic **Keychain/Keystore** se lo, UI par mat dikhao | Wallet security |
| Backend par password **log mat likho** | Audit safety |
| Deploy job **user JWT** se bind karo | Doosra user na dekhe |
| VPS par deploy ke baad SSH password change karne ko bolo | Best practice |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `sudod download failed` | `git pull` in `/opt/validator-worker` — check `SUDOD_DOWNLOAD_URL` in config |
| SSH connection failed | Galat IP/password; port 22 check |
| Insufficient balance | 1001 SUDO app wallet me bhejo |
| Syncing bahut der | Normal 30–90 min; seed se sync |
| Validator jailed | VPS: `bash scripts/unjail-validator.sh` |
| Deploy stuck | Backend logs + VPS: `tail -f /var/log/sudo-validator-install.log` |

---

## Related

| Doc | Link |
|-----|------|
| Validator server repo | https://github.com/Sudomessenger/Validator |
| Remote deploy script | `scripts/deploy-remote-validator.sh` |
| WC signing | `FLUTTER_WALLETCONNECT.md` |

---

## One-liner (Flutter + Backend team)

> User app me **Server IP + SSH Password + Moniker** daale → backend `deploy-remote-validator.sh` chalaye → app **jobId** se progress poll kare → **1001 SUDO** pehle se app wallet me ho → active par **sudoscan.io/validators** par dikhega.
