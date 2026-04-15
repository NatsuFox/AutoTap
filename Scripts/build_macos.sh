#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

require_macos

configuration="debug"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      configuration="debug"
      ;;
    --release)
      configuration="release"
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./Scripts/build_macos.sh [--debug|--release]

Builds the AutoTap Swift package on macOS and writes a timestamped build log.
Logs default to ./logs/build/ inside the project directory unless AUTOTAP_LOG_ROOT is set.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

build_log="$(new_log_file build "build-${configuration}")"
build_package "$configuration" "$build_log"

cat <<EOF
Build finished.
Binary: ${AUTOTAP_BINARY_PATH}
Build log: ${build_log}
EOF
