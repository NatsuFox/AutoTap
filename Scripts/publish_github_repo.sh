#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OWNER="${AUTOTAP_GITHUB_OWNER:-NatsuFox}"
REPO_NAME="${AUTOTAP_GITHUB_REPO:-AutoTap}"
VISIBILITY="${AUTOTAP_GITHUB_VISIBILITY:-public}"
DESCRIPTION="${AUTOTAP_GITHUB_DESCRIPTION:-A simple macOS auto-clicker with safe controls}"
USER_NAME="${AUTOTAP_GIT_USER_NAME:-NatsuFox}"
USER_EMAIL="${AUTOTAP_GIT_USER_EMAIL:-268350328+NatsuFox@users.noreply.github.com}"
DEFAULT_BRANCH="${AUTOTAP_GIT_BRANCH:-main}"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

usage() {
  cat <<'EOF'
Usage: ./Scripts/publish_github_repo.sh [options]

Creates the GitHub repository for AutoTap under NatsuFox and pushes the local main branch.
If GITHUB_TOKEN or GH_TOKEN is not already set, the script will prompt for a token securely.

Options:
  --owner <owner>           GitHub owner/username (default: NatsuFox)
  --repo <repo>             GitHub repo name (default: AutoTap)
  --public                  Create a public repo (default)
  --private                 Create a private repo
  --description <text>      GitHub repo description
  --branch <branch>         Local branch to push (default: main)
  -h, --help                Show help

Environment overrides:
  AUTOTAP_GITHUB_OWNER
  AUTOTAP_GITHUB_REPO
  AUTOTAP_GITHUB_VISIBILITY
  AUTOTAP_GITHUB_DESCRIPTION
  AUTOTAP_GIT_USER_NAME
  AUTOTAP_GIT_USER_EMAIL
  AUTOTAP_GIT_BRANCH
  GITHUB_TOKEN / GH_TOKEN
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)
      shift
      OWNER="${1:?Missing value for --owner}"
      ;;
    --repo)
      shift
      REPO_NAME="${1:?Missing value for --repo}"
      ;;
    --public)
      VISIBILITY="public"
      ;;
    --private)
      VISIBILITY="private"
      ;;
    --description)
      shift
      DESCRIPTION="${1:?Missing value for --description}"
      ;;
    --branch)
      shift
      DEFAULT_BRANCH="${1:?Missing value for --branch}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

if ! command -v git >/dev/null 2>&1; then
  echo "git is required but not installed." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required but not installed." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but not installed." >&2
  exit 1
fi

if [[ ! -d "${REPO_ROOT}/.git" ]]; then
  echo "No git repository found at ${REPO_ROOT}. Initialize it before publishing." >&2
  exit 1
fi

if ! git -C "${REPO_ROOT}" rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "No commits found in ${REPO_ROOT}. Create an initial commit before publishing." >&2
  exit 1
fi

if [[ -z "${TOKEN}" ]]; then
  printf 'GitHub token for %s (input hidden): ' "$OWNER"
  stty -echo
  IFS= read -r TOKEN
  stty echo
  printf '\n'
fi

if [[ -z "${TOKEN}" ]]; then
  echo "A GitHub token is required." >&2
  exit 1
fi

repo_payload="$(OWNER="$OWNER" REPO_NAME="$REPO_NAME" DESCRIPTION="$DESCRIPTION" VISIBILITY="$VISIBILITY" python3 - <<'PY'
import json, os
payload = {
    'name': os.environ['REPO_NAME'],
    'description': os.environ['DESCRIPTION'],
    'private': os.environ['VISIBILITY'] == 'private',
}
print(json.dumps(payload))
PY
)"

response_file="$(mktemp)"
cleanup() {
  rm -f "$response_file" "${ASKPASS:-}"
}
trap cleanup EXIT INT TERM

http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
  -X POST \
  -H 'Accept: application/vnd.github+json' \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  -H 'Content-Type: application/json' \
  https://api.github.com/user/repos \
  -d "$repo_payload")"

if [[ "$http_code" == "201" ]]; then
  echo "GitHub repo created: https://github.com/${OWNER}/${REPO_NAME}"
elif [[ "$http_code" == "422" ]] && grep -qi 'name already exists on this account' "$response_file"; then
  echo "GitHub repo already exists: https://github.com/${OWNER}/${REPO_NAME}"
else
  echo "GitHub API request failed (HTTP ${http_code})." >&2
  cat "$response_file" >&2
  exit 1
fi

git -C "$REPO_ROOT" config user.name "$USER_NAME"
git -C "$REPO_ROOT" config user.email "$USER_EMAIL"
git -C "$REPO_ROOT" config credential.username "$OWNER"

git -C "$REPO_ROOT" remote remove origin >/dev/null 2>&1 || true
git -C "$REPO_ROOT" remote add origin "https://github.com/${OWNER}/${REPO_NAME}.git"

ASKPASS="$(mktemp)"
cat > "$ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "${AUTOTAP_GITHUB_PUSH_USER}" ;;
  *Password*) printf '%s\n' "${AUTOTAP_GITHUB_PUSH_TOKEN}" ;;
  *) printf '\n' ;;
esac
EOF
chmod 700 "$ASKPASS"

AUTOTAP_GITHUB_PUSH_USER="$OWNER" \
AUTOTAP_GITHUB_PUSH_TOKEN="$TOKEN" \
GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0 \
  git -C "$REPO_ROOT" -c credential.helper= -c credential.username="$OWNER" push -u origin "$DEFAULT_BRANCH"

echo "Remote bootstrap complete: https://github.com/${OWNER}/${REPO_NAME}"
