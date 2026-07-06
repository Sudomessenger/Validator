#!/usr/bin/env bash
# Publish this repository to https://github.com/Sudomessenger/Validator
#
# Usage:
#   GITHUB_TOKEN=ghp_xxxx bash scripts/publish-to-github.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${REPO:-Sudomessenger/Validator}"
BRANCH="${BRANCH:-main}"

[[ -n "${GITHUB_TOKEN:-}" ]] || {
  echo "Error: set GITHUB_TOKEN (GitHub PAT with repo scope for the Sudomessenger org)."
  exit 1
}

cd "$ROOT"

create_repo_if_missing() {
  local http
  http="$(curl -s -o /tmp/validator-repo-check.json -w "%{http_code}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}" || echo 000)"

  if [[ "$http" == "200" ]]; then
    echo "Repository already exists: https://github.com/${REPO}"
    return 0
  fi

  if [[ "$http" != "404" && "$http" != "000" ]]; then
    echo "WARN: unexpected GitHub API status ${http} while checking repo"
  fi

  echo "Creating public repository ${REPO} ..."
  local create_http
  create_http="$(curl -s -o /tmp/validator-repo-create.json -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/Sudomessenger/repos" \
    -d '{"name":"Validator","description":"Production-ready SUDO network validator deployment tooling for sudo99","private":false,"has_issues":true}' || echo 000)"

  if [[ "$create_http" == "201" ]]; then
    python3 -c "import json; print('Created:', json.load(open('/tmp/validator-repo-create.json'))['html_url'])"
    return 0
  fi

  echo ""
  echo "Could not create repo via GitHub API (HTTP ${create_http})."
  echo "Create an empty public repo manually:"
  echo "  https://github.com/organizations/Sudomessenger/repositories/new"
  echo "  Name: Validator"
  echo "Then re-run this script."
  echo ""
  return 1
}

create_repo_if_missing || true

git remote remove origin 2>/dev/null || true
git remote add origin "https://${GITHUB_TOKEN}@github.com/${REPO}.git"

echo "Pushing ${BRANCH} -> https://github.com/${REPO}"
git push -u origin "${BRANCH}"

echo ""
echo "Published: https://github.com/${REPO}"
