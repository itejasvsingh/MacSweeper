# MacSweeper

A lightweight, native SwiftUI macOS utility to reclaim "System Data", clean Docker storage, and completely uninstall apps.

## Quick Install (Recommended)
Run this single command in **Terminal**—it downloads the latest release, installs it to `/Applications`, and avoids macOS Gatekeeper warnings:

```bash
curl -fsSL [https://raw.githubusercontent.com/itejasvsingh/MacSweeper/main/install.sh](https://raw.githubusercontent.com/itejasvsingh/MacSweeper/main/install.sh) | bash
```

## Manual Download
- **[Download Latest Release (MacSweeper.zip)](https://github.com/itejasvsingh/MacSweeper/releases/latest/download/MacSweeper.zip)**
- [View All Releases](https://github.com/itejasvsingh/MacSweeper/releases/latest)

*(If you download via a browser instead of Terminal, drag **MacSweeper.app** to **Applications** and run `xattr -cr /Applications/MacSweeper.app` once.)*

## Features
- **System Data Cleaner:** Scans Claude Desktop VM bundles, Ollama models, UTM VMs, Xcode DerivedData, iOS Simulators, npm/pip/Homebrew caches, and messaging caches with plain-English safety badges.
- **Docker Cleaner:** Inspects `docker system df` and prunes unused images and build caches.
- **App Uninstaller:** Removes `.app` bundles along with hidden `~/Library` and system-wide `/Library` leftovers (with native admin prompt when needed).
- **Orphaned Leftovers:** Flags large `~/Library/Containers` folders left behind by deleted apps.
- **Auto-Updates:** Checks GitHub Releases automatically on launch and supports one-click **Install & Relaunch**.
- **Safe by Default:** Moves files to the macOS Trash instead of permanently deleting them.

## Build from Source
```bash
swift run
```
