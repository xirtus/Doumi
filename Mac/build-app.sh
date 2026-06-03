#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="Doumi"
BUNDLE_ID="com.doumi.app"
VERSION="0.1.1"
BUILD_DIR=".build/release"
APP_DIR="$APP.app"

echo "╔══════════════════════════════════╗"
echo "║  Building Doumi.app  v$VERSION   ║"
echo "╚══════════════════════════════════╝"

# ── 1. Build universal binaries ──────────────────────────────────────────────────
echo ""
echo "▸ Building universal release binaries (arm64 + x86_64)…"
swift build -c release --product DoumiApp --arch arm64 2>&1
swift build -c release --product DoumiApp --arch x86_64 2>&1
lipo -create \
  .build/arm64-apple-macosx/release/DoumiApp \
  .build/x86_64-apple-macosx/release/DoumiApp \
  -output "$BUILD_DIR/DoumiApp"

swift build -c release --product doumi --arch arm64   2>&1
swift build -c release --product doumi --arch x86_64 2>&1
lipo -create \
  .build/arm64-apple-macosx/release/doumi \
  .build/x86_64-apple-macosx/release/doumi \
  -output "$BUILD_DIR/doumi"

# ── 2. Generate icon ──────────────────────────────────────────────────────────
echo ""
echo "▸ Generating app icon…"
swift scripts/make-icon.swift

# ── 3. Assemble .app bundle ───────────────────────────────────────────────────
echo ""
echo "▸ Assembling ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/DoumiApp" "$APP_DIR/Contents/MacOS/$APP"
# CLI goes in a helper path (avoids case-insensitive filesystem collision with Doumi)
cp "$BUILD_DIR/doumi" "$APP_DIR/Contents/MacOS/doumi-cli" 2>/dev/null || true
cp AppIcon.icns           "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -f AppIcon.icns

# ── 4. Info.plist ─────────────────────────────────────────────────────────────
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>          <string>$APP</string>
    <key>CFBundleDisplayName</key>   <string>$APP</string>
    <key>CFBundleIdentifier</key>    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>       <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key>    <string>$APP</string>
    <key>CFBundleIconFile</key>      <string>AppIcon</string>
    <key>CFBundleIconName</key>      <string>AppIcon</string>
    <key>CFBundlePackageType</key>   <string>APPL</string>
    <key>NSPrincipalClass</key>      <string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSAppTransportSecurity</key>
        <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
    <key>NSHumanReadableCopyright</key>
        <string>Copyright © 2026 Doumi. GNU GPL v3.</string>
</dict>
</plist>
PLIST

echo "   ✓ $APP_DIR assembled"
echo ""
echo "┌─────────────────────────────────────┐"
echo "│  $APP.app is ready!                  │"
echo "│                                     │"
echo "│  Install:  ./install.sh             │"
echo "│  Or drag Doumi.app to /Applications │"
echo "└─────────────────────────────────────┘"
