#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINUX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APPIMAGE="$LINUX_DIR/Doumi-Linux-x86_64.AppImage"
INSTALL_DIR="${DOUMI_INSTALL_DIR:-$HOME/.local/bin}"
INSTALL_PATH="$INSTALL_DIR/Doumi.AppImage"

mkdir -p "$INSTALL_DIR"
cp "$APPIMAGE" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

echo "Installed Doumi AppImage to $INSTALL_PATH"
echo "Run it with:"
echo "  $INSTALL_PATH"
