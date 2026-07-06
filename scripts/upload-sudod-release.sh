#!/usr/bin/env bash
# One-time: upload pre-built sudod to GitHub Release (public download for deploy).
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx bash scripts/upload-sudod-release.sh [/path/to/sudod]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-/root/sudo-chain/build/sudod}"
TAG="${SUDOD_RELEASE_TAG:-v1.0.0}"
ASSET_NAME="${SUDOD_RELEASE_ASSET:-sudod-linux-amd64}"
REPO="${GITHUB_REPO:-Sudomessenger/Validator}"

[[ -n "${GITHUB_TOKEN:-}" ]] || { echo "Set GITHUB_TOKEN"; exit 1; }
[[ -f "$SRC" ]] || { echo "Binary not found: $SRC"; exit 1; }

TMP="$(mktemp)"
cp "$SRC" "$TMP"
strip "$TMP" 2>/dev/null || true
chmod +x "$TMP"

echo "==> Creating release $TAG on $REPO ..."
RESP="$(curl -s -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/releases" \
  -d "{\"tag_name\":\"${TAG}\",\"name\":\"sudod ${TAG}\",\"body\":\"Pre-built sudod (linux amd64) for validator deploy.\",\"draft\":false,\"prerelease\":false}")"

UPLOAD="$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('upload_url',''))" <<<"$RESP")"
if [[ -z "$UPLOAD" || "$UPLOAD" == "None" ]]; then
  echo "$RESP" | python3 -m json.tool 2>/dev/null || echo "$RESP"
  echo "Release may already exist — upload asset manually on GitHub Releases page."
  exit 1
fi

UPLOAD="${UPLOAD%\{?name,label\}}"
echo "==> Uploading $ASSET_NAME ($(du -h "$TMP" | awk '{print $1}')) ..."
curl -s -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$TMP" \
  "${UPLOAD}?name=${ASSET_NAME}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('browser_download_url') or d)"
rm -f "$TMP"
echo "Done. Deploy uses: https://github.com/${REPO}/releases/download/${TAG}/${ASSET_NAME}"
