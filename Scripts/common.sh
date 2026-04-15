#!/usr/bin/env bash
set -euo pipefail

AUTOTAP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOTAP_REPO_ROOT="$(cd "${AUTOTAP_SCRIPT_DIR}/.." && pwd)"
AUTOTAP_DEFAULT_LOG_ROOT="${AUTOTAP_REPO_ROOT}/logs"
AUTOTAP_LOG_ROOT="${AUTOTAP_LOG_ROOT:-${AUTOTAP_DEFAULT_LOG_ROOT}}"
AUTOTAP_SUBSYSTEM="com.natsufox.AutoTap"
AUTOTAP_PRODUCT_NAME="AutoTap"
AUTOTAP_TARGET_NAME="AutoTapApp"
AUTOTAP_BINARY_PATH=""
SWIFT_CMD=()

now_iso8601() {
  date +"%Y-%m-%dT%H:%M:%S%z"
}

timestamp_slug() {
  date +"%Y%m%d-%H%M%S"
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "These scripts are intended to run on macOS." >&2
    exit 1
  fi
}

ensure_log_dir() {
  local bucket="$1"
  local dir="${AUTOTAP_LOG_ROOT}/${bucket}"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

new_log_file() {
  local bucket="$1"
  local prefix="$2"
  local dir
  dir="$(ensure_log_dir "$bucket")"
  printf '%s/%s-%s.log\n' "$dir" "$prefix" "$(timestamp_slug)"
}

resolve_swift_cmd() {
  if [[ ${#SWIFT_CMD[@]} -gt 0 ]]; then
    return
  fi

  if command -v xcrun >/dev/null 2>&1 && xcrun --find swift >/dev/null 2>&1; then
    SWIFT_CMD=(xcrun swift)
    return
  fi

  if command -v swift >/dev/null 2>&1; then
    SWIFT_CMD=(swift)
    return
  fi

  echo "Swift toolchain not found. Install Xcode or macOS Command Line Tools first." >&2
  exit 1
}

swift_version_line() {
  resolve_swift_cmd
  "${SWIFT_CMD[@]}" --version 2>&1 | head -n 1
}

resolve_built_binary() {
  local bin_dir="$1"
  local candidate

  for candidate in "$AUTOTAP_PRODUCT_NAME" "$AUTOTAP_TARGET_NAME"; do
    if [[ -x "${bin_dir}/${candidate}" ]]; then
      AUTOTAP_BINARY_PATH="${bin_dir}/${candidate}"
      return 0
    fi
  done

  echo "Unable to find a built AutoTap executable in ${bin_dir}." >&2
  echo "Checked candidates: ${AUTOTAP_PRODUCT_NAME}, ${AUTOTAP_TARGET_NAME}" >&2
  ls -la "$bin_dir" >&2 || true
  return 1
}

resolve_binary_path() {
  local configuration="$1"
  resolve_swift_cmd

  local bin_dir
  bin_dir="$(cd "$AUTOTAP_REPO_ROOT" && "${SWIFT_CMD[@]}" build -c "$configuration" --show-bin-path 2>/dev/null)"
  resolve_built_binary "$bin_dir"
}

build_package() {
  local configuration="$1"
  local build_log="$2"

  resolve_swift_cmd

  {
    echo "[AutoTap] build started: $(now_iso8601)"
    echo "[AutoTap] repo: ${AUTOTAP_REPO_ROOT}"
    echo "[AutoTap] configuration: ${configuration}"
    echo "[AutoTap] log: ${build_log}"
    echo "[AutoTap] toolchain: $(swift_version_line)"
  } | tee "$build_log"

  (
    cd "$AUTOTAP_REPO_ROOT"
    "${SWIFT_CMD[@]}" build -c "$configuration" --product "$AUTOTAP_PRODUCT_NAME"
  ) 2>&1 | tee -a "$build_log"

  local bin_dir
  bin_dir="$(cd "$AUTOTAP_REPO_ROOT" && "${SWIFT_CMD[@]}" build -c "$configuration" --show-bin-path 2>>"$build_log")"

  if ! resolve_built_binary "$bin_dir"; then
    echo "[AutoTap] build finished compiling, but the expected executable could not be located." | tee -a "$build_log" >&2
    exit 1
  fi

  {
    echo "[AutoTap] build finished: $(now_iso8601)"
    echo "[AutoTap] binary: ${AUTOTAP_BINARY_PATH}"
  } | tee -a "$build_log"
}
