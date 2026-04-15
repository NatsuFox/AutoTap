# AutoTap

A simple macOS auto-clicker with safe controls.

AutoTap is a native macOS utility for repeating clicks on either a single point or an ordered group of points. It is built with SwiftUI, ships as a standalone macOS app, and includes practical safety controls so repetitive automation stays easier to manage.

## Highlights

- Native macOS app built with Swift Package Manager and SwiftUI
- Single-point and point-group click units
- Configurable click frequency and per-unit auto-stop timers
- Global `Esc` emergency stop while clicking or during startup countdown
- Optional startup countdown before automation begins
- Floating Mini Bar for compact control while the main window is hidden
- English and Simplified Chinese interface support
- Local history for restoring previously executed specifications
- Repo-local build, run, logging, and release scripts

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac

## Install From GitHub Releases

Download the latest release from:

- <https://github.com/NatsuFox/AutoTap/releases/latest>

Choose the archive that matches your Mac:

- `autotap-<version>-macos-arm64.zip` for Apple Silicon
- `autotap-<version>-macos-x86_64.zip` for Intel Macs
- `*-binary.tar.gz` if you want the raw executable instead of the `.app` bundle
- `*.sha256` if you want to verify the downloaded archive

Install steps:

1. Download the correct archive for your Mac.
2. Unzip it.
3. Move `AutoTap.app` into `/Applications`.
4. Launch the app.

Current releases are unsigned. On first launch, macOS Gatekeeper may warn about the app. If that happens, right-click `AutoTap.app`, choose `Open`, and confirm the prompt.

## Run From Source

AutoTap includes helper scripts for building, running, and packaging the app on macOS.

Run a debug build directly:

```bash
./Scripts/run_macos.sh
```

Run without rebuilding first:

```bash
./Scripts/run_macos.sh --skip-build
```

Build a release bundle locally:

```bash
./Scripts/release_macos.sh --release --version 0.1.1
```

Run the Swift test target:

```bash
swift test
```

## Logs

When you launch the app through `./Scripts/run_macos.sh`, AutoTap writes timestamped logs into the repo-local `logs/` directory.

- `logs/build/` stores build output
- `logs/run/` stores stdout, stderr, and unified logging captures

This makes it easier to inspect runtime issues without relying on Xcode.

## Safety Notes

AutoTap is designed for repetitive input automation, so safety controls matter.

- Press `Esc` to stop active clicking immediately.
- A startup countdown can be enabled to give you time to cancel before automation begins.
- Accessibility permission is required before the app can send clicks.
- Per-unit timers can stop individual units automatically.

## Project Structure

- [Package.swift](Package.swift) defines the Swift package targets
- [Sources/AutoTapCore](Sources/AutoTapCore) contains click models, persistence, logging, and engine logic
- [Sources/AutoTapApp](Sources/AutoTapApp) contains the macOS UI, settings panel, and Mini Bar
- [Scripts/run_macos.sh](Scripts/run_macos.sh) builds and launches the app with log capture
- [Scripts/release_macos.sh](Scripts/release_macos.sh) creates distributable macOS release artifacts
- [Scripts/tag_release.sh](Scripts/tag_release.sh) creates and optionally pushes version tags
- [.github/workflows/release.yml](.github/workflows/release.yml) publishes macOS assets to GitHub Releases on `v*` tags

## Releasing

To publish a new GitHub release:

```bash
./Scripts/tag_release.sh 0.1.2 --push
```

That pushes a `v0.1.2` tag and triggers the GitHub Actions release workflow, which builds:

- Apple Silicon `.zip`
- Intel `.zip`
- Apple Silicon raw binary archive
- Intel raw binary archive
- checksum files for each archive

## License

No license file is included yet.
