#!/usr/bin/env bash
# Upload pre-built sudod + libwasmvm to GitHub Release (public download for deploy).
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx bash scripts/upload-sudod-release.sh [/path/to/sudod] [/path/to/libwasmvm.so]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-/root/sudo-chain/build/sudod}"
WASMVM_SRC="${2:-}"
TAG="${SUDOD_RELEASE_TAG:-v1.0.1}"
REPO="${GITHUB_REPO:-Sudomessenger/Validator}"

[[ -n "${GITHUB_TOKEN:-}" ]] || { echo "Set GITHUB_TOKEN"; exit 1; }
[[ -f "$SRC" ]] || { echo "Binary not found: $SRC"; exit 1; }

if [[ -z "$WASMVM_SRC" ]]; then
  WASMVM_SRC="$(find /root/go/pkg/mod -path '*wasmvm/v2@*/internal/api/libwasmvm.x86_64.so' 2>/dev/null | head -1 || true)"
fi
[[ -f "$WASMVM_SRC" ]] || { echo "libwasmvm not found: $WASMVM_SRC"; exit 1; }

TMP="$(mktemp)"
cp "$SRC" "$TMP"
strip "$TMP" 2>/dev/null || true
chmod +x "$TMP"

create_or_get_upload_url() {
  local resp upload
  resp="$(curl -s -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/releases" \
    -d "{\"tag_name\":\"${TAG}\",\"name\":\"sudod ${TAG}\",\"body\":\"Pre-built sudod + libwasmvm for validator deploy (Ubuntu/Debian x86_64).\",\"draft\":false,\"prerelease\":false}")"
  upload="$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('upload_url',''))" <<<"$resp")"
  if [[ -z "$upload" || "$upload" == "None" ]]; then
    resp="$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
      "https://api.github.com/repos/${REPO}/releases/tags/${TAG}")"
    upload="$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('upload_url',''))" <<<"$resp")"
  fi
  [[ -n "$upload" && "$upload" != "None" ]] || {
    echo "$resp" | python3 -m json.tool 2>/dev/null || echo "$resp"
    exit 1
  }
  printf '%s' "${upload%\{?name,label\}}"
}

upload_asset() {
  local file="$1" name="$2" upload_url="$3"
  echo "==> Uploading $name ($(du -h "$file" | awk '{print $1}')) ..."
  curl -s -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$file" \
    "${upload_url}?name=${name}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('browser_download_url') or d)"
}

UPLOAD_URL="$(create_or_get_upload_url)"
upload_asset "$TMP" "sudod-linux-amd64" "$UPLOAD_URL"
upload_asset "$WASMVM_SRC" "libwasmvm.x86_64.so" "$UPLOAD_URL"
rm -f "$TMP"

echo "Done."
echo "  sudod:  https://github.com/${REPO}/releases/download/${TAG}/sudod-linux-amd64"
echo "  lib:    https://github.com/${REPO}/releases/download/${TAG}/libwasmvm.x86_64.so"
