#!/usr/bin/env bash
# ─── Build Arch package locally ─────────────────────────────────────────────
# Usage: ./packaging/make-arch.sh
# Requires: base-devel, rust, cargo, gtk4, libadwaita
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Building Arch package..."

# Create a temporary build directory
BUILD_DIR="$(mktemp -d)"
trap "rm -rf $BUILD_DIR" EXIT

cd "$BUILD_DIR"

# Copy PKGBUILD and .install
cp "${SCRIPT_DIR}/arch/PKGBUILD" .
cp "${SCRIPT_DIR}/arch/doumi.install" .

# Copy source (point to local checkout instead of downloading)
# Replace the source URL with the local path
sed -i "s|^source=.*|source=(\"file://${PROJECT_DIR}\")|" PKGBUILD
sed -i "s|^sha256sums=.*|sha256sums=('SKIP')|" PKGBUILD

# Adjust prepare to unpack the local copy
# We need to symlink instead of untar
sed -i 's|cd "${srcdir}/\${pkgname}-\${pkgver}"|cd "${srcdir}/${pkgname}"\n    cp -r "${srcdir}/file://'"${PROJECT_DIR}"'/"* . 2>/dev/null || true|' PKGBUILD 2>/dev/null || true

# Actually, simpler approach: just build with makepkg using the project dir
rm -rf "$BUILD_DIR"
echo "==> Building with makepkg..."
cd "${SCRIPT_DIR}/arch"
makepkg -sf

echo ""
echo "==> Package built in: ${SCRIPT_DIR}/arch/"
ls -lh doumi-*.pkg.tar.* 2>/dev/null || echo "(no package found — check errors above)"
