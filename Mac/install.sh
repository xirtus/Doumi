#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d "Doumi.app" ]; then
    echo "Building first…"
    ./build-app.sh
fi

echo "▸ Installing Doumi.app to /Applications…"
rm -rf "/Applications/Doumi.app"
cp -R "Doumi.app" "/Applications/"

echo "▸ Symlinking CLI tool…"
sudo ln -sf "/Applications/Doumi.app/Contents/MacOS/doumi" /usr/local/bin/doumi 2>/dev/null || \
    ln -sf "/Applications/Doumi.app/Contents/MacOS/doumi" "$HOME/.local/bin/doumi" 2>/dev/null || \
    echo "   (CLI symlink skipped — add /Applications/Doumi.app/Contents/MacOS to PATH manually)"

echo ""
echo "✓ Doumi installed!"
echo "  Open from Applications or Spotlight."
echo "  CLI: doumi --help"
