#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

require_macos

configuration="debug"
skip_build=0
build_log=""
log_stream_pid=""

cleanup() {
  if [[ -n "$log_stream_pid" ]]; then
    kill "$log_stream_pid" >/dev/null 2>&1 || true
    wait "$log_stream_pid" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      configuration="debug"
      ;;
    --release)
      configuration="release"
      ;;
    --skip-build)
      skip_build=1
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./Scripts/run_macos.sh [--debug|--release] [--skip-build]

Builds AutoTap if needed, then launches the executable directly from SwiftPM output.
Runtime stdout/stderr and unified OSLog output are captured into timestamped log files.
Logs default to ./logs/run/ inside the project directory unless AUTOTAP_LOG_ROOT is set.
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

if [[ "$skip_build" -eq 0 ]]; then
  build_log="$(new_log_file build "build-${configuration}")"
  build_package "$configuration" "$build_log"
else
  resolve_binary_path "$configuration"
  if [[ ! -x "$AUTOTAP_BINARY_PATH" ]]; then
    echo "Executable not found at ${AUTOTAP_BINARY_PATH}. Run without --skip-build first." >&2
    exit 1
  fi
fi

run_stdout_log="$(new_log_file run "run-stdout-${configuration}")"
run_oslog_log="$(new_log_file run "run-oslog-${configuration}")"

{
  echo "[AutoTap] run started: $(now_iso8601)"
  echo "[AutoTap] repo: ${AUTOTAP_REPO_ROOT}"
  echo "[AutoTap] binary: ${AUTOTAP_BINARY_PATH}"
  echo "[AutoTap] stdout log: ${run_stdout_log}"
  echo "[AutoTap] unified log: ${run_oslog_log}"
  if [[ -n "$build_log" ]]; then
    echo "[AutoTap] build log: ${build_log}"
  fi
} | tee "$run_stdout_log"

if command -v log >/dev/null 2>&1; then
  log stream \
    --style compact \
    --level debug \
    --predicate "subsystem == \"${AUTOTAP_SUBSYSTEM}\"" \
    > "$run_oslog_log" 2>&1 &
  log_stream_pid="$!"
  echo "[AutoTap] log stream pid: ${log_stream_pid}" | tee -a "$run_stdout_log"
else
  echo "[AutoTap] warning: macOS unified logging command not found; OSLog capture disabled." | tee -a "$run_stdout_log"
fi

(
  cd "$AUTOTAP_REPO_ROOT"
  NSUnbufferedIO=YES "$AUTOTAP_BINARY_PATH"
) 2>&1 | tee -a "$run_stdout_log"
app_exit=${PIPESTATUS[0]}

echo "[AutoTap] app exited with code ${app_exit} at $(now_iso8601)" | tee -a "$run_stdout_log"

exit "$app_exit"
