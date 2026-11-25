#!/bin/bash
set -euo pipefail

REPO="itejasvsingh/MacSweeper"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
APP="/Applications/MacSweeper.app"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading latest MacSweeper..."
curl -fsSL "$BASE_URL/MacSweeper.zip" -o "$TMP_DIR/MacSweeper.zip"
curl -fsSL "$BASE_URL/MacSweeper.zip.sha256" -o "$TMP_DIR/MacSweeper.zip.sha256" || {
  echo "Error: checksum file not found for this release. Aborting." >&2
  exit 1
}

echo "Verifying download..."
EXPECTED=$(awk '{print $1}' "$TMP_DIR/MacSweeper.zip.sha256")
ACTUAL=$(shasum -a 256 "$TMP_DIR/MacSweeper.zip" | awk '{print $1}')
if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "Error: checksum mismatch. The download may be corrupted or tampered with. Aborting." >&2
  exit 1
fi

echo "Extracting MacSweeper.app..."
ditto -xk "$TMP_DIR/MacSweeper.zip" "$TMP_DIR/extract"
NEW_APP="$TMP_DIR/extract/MacSweeper.app"
[ -d "$NEW_APP" ] || { echo "Error: MacSweeper.app not found in download." >&2; exit 1; }

# Verify the signature the release was built with instead of re-signing it.
codesign --verify --deep --strict "$NEW_APP" || {
  echo "Error: code signature verification failed. Aborting." >&2
  exit 1
}

echo "Installing to /Applications..."
pkill -x MacSweeper 2>/dev/null || true

# Keep the old copy until the new one is in place, so a failed move can't leave you with nothing.
BACKUP="$TMP_DIR/MacSweeper-previous.app"
if [ -e "$APP" ]; then
  mv "$APP" "$BACKUP"
fi
if ! mv "$NEW_APP" "$APP"; then
  echo "Error: could not install to /Applications. Restoring previous version." >&2
  [ -e "$BACKUP" ] && mv "$BACKUP" "$APP"
  exit 1
fi

echo "Done! Launching MacSweeper..."
open "$APP"
