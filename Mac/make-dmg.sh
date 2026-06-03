#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="Doumi"
VERSION="0.1.0"
DMG="$APP-$VERSION.dmg"
STAGING="/tmp/doumi-dmg-$$"

if [ ! -d "$APP.app" ]; then
    echo "Error: $APP.app not found. Run ./build-app.sh first."
    exit 1
fi

echo "▸ Creating installer DMG…"
rm -f "$DMG"
rm -rf "$STAGING"
mkdir -p "$STAGING"

cp -R "$APP.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Create a simple DMG with auto-open background
hdiutil create \
    -volname "$APP $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG"

rm -rf "$STAGING"

echo "✓ Created $DMG ($(du -sh "$DMG" | cut -f1))"
echo ""
echo "  Share $DMG — users open it and drag Doumi to Applications."
