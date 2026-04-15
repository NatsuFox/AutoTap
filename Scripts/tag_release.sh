#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage: ./Scripts/tag_release.sh <version> [--push]

Create an annotated release tag from the current HEAD commit.

Examples:
  ./Scripts/tag_release.sh 0.1.0
  ./Scripts/tag_release.sh v0.1.0 --push

Options:
  --push      Push the created tag to origin after creating it locally
  -h, --help  Show this help text
EOF
}

push_tag=0
version=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      push_tag=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -n "$version" ]]; then
        echo "Unexpected argument: $1" >&2
        exit 2
      fi
      version="$1"
      ;;
  esac
  shift
done

if [[ -z "$version" ]]; then
  usage >&2
  exit 2
fi

tag="$version"
if [[ "$tag" != v* ]]; then
  tag="v${tag}"
fi

if ! git -C "${AUTOTAP_REPO_ROOT}" rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "Repository does not have a valid HEAD commit yet." >&2
  exit 1
fi

if ! git -C "${AUTOTAP_REPO_ROOT}" check-ref-format "refs/tags/${tag}" >/dev/null 2>&1; then
  echo "Invalid tag name: ${tag}" >&2
  exit 1
fi

if git -C "${AUTOTAP_REPO_ROOT}" rev-parse --verify "refs/tags/${tag}" >/dev/null 2>&1; then
  echo "Tag already exists: ${tag}" >&2
  exit 1
fi

git -C "${AUTOTAP_REPO_ROOT}" tag -a "$tag" -m "Release ${tag}"
echo "Created tag ${tag} at $(git -C "${AUTOTAP_REPO_ROOT}" rev-parse --short HEAD)."

if [[ "$push_tag" -eq 1 ]]; then
  git -C "${AUTOTAP_REPO_ROOT}" push origin "$tag"
  echo "Pushed ${tag} to origin. The GitHub release workflow should start automatically."
else
  cat <<EOF
Tag ${tag} is local only.
Next steps:
  git -C ${AUTOTAP_REPO_ROOT} push origin ${tag}
Or open GitHub Actions and run the 'Release macOS' workflow manually.
EOF
fi
