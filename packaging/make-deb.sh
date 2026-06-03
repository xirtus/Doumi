#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
PKG_NAME="doumi"
PKG_VER="0.1.0"
PKG_ARCH="amd64"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="/tmp/doumi-deb-build"
PKG_DIR="${BUILD_DIR}/${PKG_NAME}_${PKG_VER}_${PKG_ARCH}"

echo "==> Cleaning build dir..."
rm -rf "$BUILD_DIR"
mkdir -p "${PKG_DIR}/usr/bin"
mkdir -p "${PKG_DIR}/usr/share/applications"
mkdir -p "${PKG_DIR}/usr/share/icons/hicolor"
mkdir -p "${PKG_DIR}/usr/lib/systemd/user"
mkdir -p "${PKG_DIR}/usr/share/doc/${PKG_NAME}"

# ─── Build project ──────────────────────────────────────────────────────────
echo "==> Building release binaries..."
cd "$PROJECT_DIR"
cargo build --release

RELEASE_DIR="$(find target -maxdepth 3 -type f -name doumi -path '*/release/*' | head -1 | xargs dirname)"
echo "    Binaries in: $RELEASE_DIR"

# Strip binaries to reduce size
echo "==> Installing and stripping binaries..."
for bin in doumi doumid doumi-gui; do
    if [ -f "${RELEASE_DIR}/${bin}" ]; then
        cp "${RELEASE_DIR}/${bin}" "${PKG_DIR}/usr/bin/${bin}"
        strip --strip-unneeded "${PKG_DIR}/usr/bin/${bin}" 2>/dev/null || true
        chmod 755 "${PKG_DIR}/usr/bin/${bin}"
        echo "    ${bin} ($(du -h "${PKG_DIR}/usr/bin/${bin}" | cut -f1))"
    else
        echo "    WARNING: ${bin} not found, skipping"
    fi
done

# ─── Icons ───────────────────────────────────────────────────────────────────
echo "==> Installing icons..."
for size in 16 32 48 64 128 256 512; do
    src="${PROJECT_DIR}/data/icons/doumi_${size}.png"
    destdir="${PKG_DIR}/usr/share/icons/hicolor/${size}x${size}/apps"
    if [ -f "$src" ]; then
        mkdir -p "$destdir"
        cp "$src" "${destdir}/doumi.png"
    fi
done
if [ -f "${PROJECT_DIR}/data/icons/doumi.svg" ]; then
    mkdir -p "${PKG_DIR}/usr/share/icons/hicolor/scalable/apps"
    cp "${PROJECT_DIR}/data/icons/doumi.svg" "${PKG_DIR}/usr/share/icons/hicolor/scalable/apps/doumi.svg"
fi

# ─── Desktop entry ──────────────────────────────────────────────────────────
echo "==> Installing desktop entry..."
cat > "${PKG_DIR}/usr/share/applications/doumi.desktop" << 'DESKTOP'
[Desktop Entry]
Name=Doumi
GenericName=File Organizer
Comment=Intelligent file organization rules for Linux
Exec=doumi gui
Icon=doumi
Terminal=false
Type=Application
Categories=Utility;FileManager;
Keywords=file;organize;automate;rules;hazel;
StartupWMClass=doumi
DESKTOP

# ─── Systemd user unit ─────────────────────────────────────────────────────
echo "==> Installing systemd user unit..."
cat > "${PKG_DIR}/usr/lib/systemd/user/doumi.service" << 'UNIT'
[Unit]
Description=Doumi file organizer daemon
Documentation=https://github.com/doumi/doumi
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/doumid
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=doumid

[Install]
WantedBy=default.target
UNIT

# ─── Copyright / docs ───────────────────────────────────────────────────────
cat > "${PKG_DIR}/usr/share/doc/${PKG_NAME}/copyright" << 'CR'
Doumi - Intelligent file organizer for Linux

Licensed under the MIT License.
CR

# ─── DEBIAN control metadata ────────────────────────────────────────────────
echo "==> Creating DEBIAN metadata..."
DEBIAN_DIR="${PKG_DIR}/DEBIAN"
mkdir -p "$DEBIAN_DIR"
cp "${SCRIPT_DIR}/debian/control" "$DEBIAN_DIR/control"

# Calculate installed size in KB
INSTALLED_SIZE=$(du -sk "$PKG_DIR" | cut -f1)
# Subtract DEBIAN dir size from installed size
DEBIAN_SIZE=$(du -sk "$DEBIAN_DIR" | cut -f1)
INSTALLED_SIZE=$(( INSTALLED_SIZE - DEBIAN_SIZE ))
echo "Installed-Size: $INSTALLED_SIZE" >> "${DEBIAN_DIR}/control"

# Copy maintainer scripts
cp "${SCRIPT_DIR}/debian/postinst" "${DEBIAN_DIR}/postinst"
cp "${SCRIPT_DIR}/debian/prerm" "${DEBIAN_DIR}/prerm"

# ─── Build .deb ─────────────────────────────────────────────────────────────
echo "==> Building .deb package..."
OUTPUT="${PROJECT_DIR}/target/${PKG_NAME}_${PKG_VER}_${PKG_ARCH}.deb"

# Use dpkg-deb if available, otherwise fall back to tar+ar
if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb --build "${PKG_DIR}" "$OUTPUT"
else
    echo "    dpkg-deb not found, building manually with ar/tar..."
    cd "$PKG_DIR"
    # Create control.tar.xz from DEBIAN/
    tar -cJf "${BUILD_DIR}/control.tar.xz" -C "${PKG_DIR}" DEBIAN/
    # Create data.tar.xz from everything except DEBIAN/
    find . -mindepth 1 -maxdepth 1 -not -name DEBIAN | \
        tar -cJf "${BUILD_DIR}/data.tar.xz" --files-from=-
    # debian-binary
    echo "2.0" > "${BUILD_DIR}/debian-binary"
    # Assemble .deb
    ar rcs "$OUTPUT" \
        "${BUILD_DIR}/debian-binary" \
        "${BUILD_DIR}/control.tar.xz" \
        "${BUILD_DIR}/data.tar.xz"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Package built: $OUTPUT"
echo "  Size: $(du -h "$OUTPUT" | cut -f1)"
echo ""
echo "  Install:  sudo dpkg -i $OUTPUT"
echo "  Remove:   sudo dpkg -r doumi"
echo "  Purge:    sudo dpkg -P doumi"
echo "═══════════════════════════════════════════════════════════════"

# Cleanup
rm -rf "$BUILD_DIR"
