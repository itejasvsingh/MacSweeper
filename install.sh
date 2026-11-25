#!/bin/bash
set -e

REPO="itejasvsingh/MacSweeper"
ZIP_URL="https://github.com/${REPO}/releases/latest/download/MacSweeper.zip"
TMP_DIR=$(mktemp -d)

echo "Downloading latest MacSweeper..."
curl -fsSL "$ZIP_URL" -o "$TMP_DIR/MacSweeper.zip"

echo "Extracting MacSweeper.app..."
ditto -xk "$TMP_DIR/MacSweeper.zip" "$TMP_DIR"

echo "Installing to /Applications..."
pkill -x MacSweeper 2>/dev/null || true
rm -rf /Applications/MacSweeper.app
mv "$TMP_DIR/MacSweeper.app" /Applications/MacSweeper.app

xattr -cr /Applications/MacSweeper.app 2>/dev/null || true
codesign --force --deep --sign - /Applications/MacSweeper.app 2>/dev/null || true
rm -rf "$TMP_DIR"

echo "Done! Launching MacSweeper..."
open /Applications/MacSweeper.app
