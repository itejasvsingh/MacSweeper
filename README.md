# MacSweeper

A lightweight, native SwiftUI macOS utility to reclaim "System Data", clean Docker storage, and completely uninstall apps.

## Download
- **[Download Latest Release (MacSweeper.zip)](https://github.com/itejasvsingh/MacSweeper/releases/latest/download/MacSweeper.zip)**
- [View All Releases](https://github.com/itejasvsingh/MacSweeper/releases/latest)

## Installation
1. Unzip **MacSweeper.zip** and drag **MacSweeper.app** into your **Applications** folder.
2. Because this is an unsigned open-source build, run this once in **Terminal** if macOS Gatekeeper blocks the first launch:
   ```bash
   xattr -cr /Applications/MacSweeper.app
   ```
3. Open **MacSweeper** and click **Full Disk Access** in the top bar if you want it to scan protected messaging folders (WhatsApp/Telegram).

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
