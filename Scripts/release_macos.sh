#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

require_macos

configuration="release"
skip_build=0
release_version="${AUTOTAP_RELEASE_VERSION:-$(date +"%Y.%m.%d")}"
bundle_identifier="${AUTOTAP_BUNDLE_ID:-com.natsufox.AutoTap}"
app_name="${AUTOTAP_APP_NAME:-AutoTap}"
app_description="${AUTOTAP_APP_DESCRIPTION:-A simple macOS auto-clicker with safe controls}"
codesign_identity="${AUTOTAP_CODESIGN_IDENTITY:-}"
icon_path="${AUTOTAP_APP_ICON:-}"
arch="$(uname -m)"
build_log=""

usage() {
  cat <<'EOF'
Usage: ./Scripts/release_macos.sh [options]

Builds a distributable macOS release artifact for AutoTap.
The script creates:
  1. A macOS .app bundle
  2. A zipped .app artifact suitable for GitHub Releases
  3. A SHA-256 checksum file for the archive

Options:
  --debug                     Build a debug artifact instead of release
  --release                   Build a release artifact (default)
  --skip-build                Reuse the existing SwiftPM build output
  --version <version>         Release version string for Info.plist and artifact names
  --bundle-id <bundle-id>     CFBundleIdentifier to write into the app bundle
  --app-name <name>           App bundle display name (default: AutoTap)
  --codesign-identity <id>    Optional codesign identity for the .app bundle
  --icon <path>               Optional .icns file to include as the app icon
  -h, --help                  Show this help text

Environment overrides:
  AUTOTAP_RELEASE_VERSION
  AUTOTAP_BUNDLE_ID
  AUTOTAP_APP_NAME
  AUTOTAP_APP_DESCRIPTION
  AUTOTAP_CODESIGN_IDENTITY
  AUTOTAP_APP_ICON

Output:
  dist/<app-name>-<version>-macos-<arch>.zip
EOF
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' /' '--'
}

make_info_plist() {
  local plist_path="$1"
  local executable_name="$2"
  local version="$3"
  local bundle_id="$4"
  local icon_file="$5"

  cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${app_name}</string>
  <key>CFBundleExecutable</key>
  <string>${executable_name}</string>
  <key>CFBundleIdentifier</key>
  <string>${bundle_id}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${app_name}</string>
  <key>CFBundleGetInfoString</key>
  <string>${app_description}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${version}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
$(if [[ -n "$icon_file" ]]; then cat <<ICON
  <key>CFBundleIconFile</key>
  <string>${icon_file}</string>
ICON
fi)
</dict>
</plist>
EOF
}

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
    --version)
      shift
      release_version="${1:?Missing value for --version}"
      ;;
    --bundle-id)
      shift
      bundle_identifier="${1:?Missing value for --bundle-id}"
      ;;
    --app-name)
      shift
      app_name="${1:?Missing value for --app-name}"
      ;;
    --codesign-identity)
      shift
      codesign_identity="${1:?Missing value for --codesign-identity}"
      ;;
    --icon)
      shift
      icon_path="${1:?Missing value for --icon}"
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

if [[ -n "$icon_path" && ! -f "$icon_path" ]]; then
  echo "Icon file not found: ${icon_path}" >&2
  exit 1
fi

if [[ "$skip_build" -eq 0 ]]; then
  build_log="$(new_log_file build "build-${configuration}-release")"
  build_package "$configuration" "$build_log"
else
  resolve_binary_path "$configuration"
  if [[ ! -x "$AUTOTAP_BINARY_PATH" ]]; then
    echo "Executable not found at ${AUTOTAP_BINARY_PATH}. Run without --skip-build first." >&2
    exit 1
  fi
fi

artifact_slug="$(slugify "${app_name}")-${release_version}-macos-${arch}"
dist_root="${AUTOTAP_REPO_ROOT}/dist"
staging_root="${dist_root}/.staging/${artifact_slug}"
app_bundle_dir="${staging_root}/${app_name}.app"
contents_dir="${app_bundle_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"
zip_path="${dist_root}/${artifact_slug}.zip"
zip_sha_path="${zip_path}.sha256"

rm -rf "${staging_root}"
mkdir -p "${macos_dir}" "${resources_dir}" "${dist_root}"

cp "${AUTOTAP_BINARY_PATH}" "${macos_dir}/${app_name}"
chmod 755 "${macos_dir}/${app_name}"

icon_file_name=""
if [[ -n "$icon_path" ]]; then
  icon_file_name="$(basename "$icon_path")"
  cp "$icon_path" "${resources_dir}/${icon_file_name}"
fi

make_info_plist "${contents_dir}/Info.plist" "${app_name}" "${release_version}" "${bundle_identifier}" "${icon_file_name}"
printf 'APPL????' > "${contents_dir}/PkgInfo"

if [[ -n "$codesign_identity" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$codesign_identity" "${app_bundle_dir}"
else
  echo "[AutoTap] warning: release bundle is unsigned and not notarized. macOS will likely show an 'Apple could not verify' warning on first launch." >&2
  echo "[AutoTap] warning: to avoid the Gatekeeper warning, ship a Developer ID signed and notarized app bundle." >&2
fi

rm -f "${zip_path}" "${zip_sha_path}"

ditto -c -k --sequesterRsrc --keepParent "${app_bundle_dir}" "${zip_path}"
shasum -a 256 "${zip_path}" > "${zip_sha_path}"

cat <<EOF
Release artifacts created.
Configuration: ${configuration}
Version: ${release_version}
Bundle ID: ${bundle_identifier}
Description: ${app_description}
Executable: ${AUTOTAP_BINARY_PATH}
App bundle: ${app_bundle_dir}
ZIP artifact: ${zip_path}
ZIP checksum: ${zip_sha_path}
$(if [[ -n "$build_log" ]]; then printf 'Build log: %s
' "$build_log"; fi)
EOF
