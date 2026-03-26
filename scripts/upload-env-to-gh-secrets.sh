#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${1:-$PROJECT_DIR/.env}"
REPO="${2:-}"

usage() {
  cat <<'EOF'
Upload KEY=value entries from a .env file to GitHub Actions secrets.

Usage:
  scripts/upload-env-to-gh-secrets.sh [ENV_FILE] [owner/repo]

Defaults:
  ENV_FILE = mobile/.env
  owner/repo is auto-detected from git or gh when omitted
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: GitHub CLI (gh) is not installed." >&2
  exit 1
fi

[[ -f "$ENV_FILE" ]] || {
  echo "Error: env file not found: $ENV_FILE" >&2
  exit 1
}

if [[ -z "$REPO" ]]; then
  if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    origin_url="$(git -C "$PROJECT_DIR" config --get remote.origin.url || true)"
    if [[ "$origin_url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
      REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
  fi
fi

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi

if [[ -z "$REPO" ]]; then
  echo "Error: Unable to determine GitHub repo. Pass it explicitly as the 2nd arg (owner/repo)." >&2
  exit 1
fi

echo "Source env file: $ENV_FILE"
echo "Target repo: $REPO"

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue

  if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[2]}"
    value="${BASH_REMATCH[3]}"

    if [[ "$value" =~ ^\"(.*)\"$ ]]; then
      value="${BASH_REMATCH[1]}"
    elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$value" ]]; then
      echo "Error: Empty value for key $key in $ENV_FILE" >&2
      exit 1
    fi

    printf '%s' "$value" | gh secret set "$key" --repo "$REPO"
    echo "Set $key"
  else
    echo "Error: Invalid line in $ENV_FILE: $line" >&2
    exit 1
  fi
done < "$ENV_FILE"
