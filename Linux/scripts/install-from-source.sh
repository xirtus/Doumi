#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINUX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCHIVE="$LINUX_DIR/Doumi-Linux-rust-source.tar.gz"
WORK_DIR="$(mktemp -d)"

tar -xzf "$ARCHIVE" -C "$WORK_DIR"
cd "$WORK_DIR"
./install.sh

echo "Source install completed from $ARCHIVE"
