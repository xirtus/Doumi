#!/bin/sh
set -eu

# Doumi BSD installer
# Supports: FreeBSD, NetBSD, OpenBSD, DragonFly BSD

OS="$(uname -s)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${CARGO_TARGET_DIR:-${SCRIPT_DIR}/target}"
INSTALL_BIN="${HOME}/.local/bin"
INSTALL_DESKTOP="${HOME}/.local/share/applications"
INSTALL_ICONS="${HOME}/.local/share/icons/hicolor"

echo "==> Doumi installer for BSD"
echo "    Detected OS: ${OS}"

# Check for cargo
if ! command -v cargo >/dev/null 2>&1; then
	echo "ERROR: cargo not found. Install Rust from: https://rustup.rs"
	echo "  Or via pkg: pkg install rust"
	exit 1
fi

# Install build dependencies hint
echo ""
echo "==> Build dependencies (install if missing):"
case "${OS}" in
	FreeBSD)
		echo "    pkg install rust gtk4 libadwaita pkgconf bash dbus sqlite3"
		;;
	NetBSD)
		echo "    pkgin install rust gtk4 libadwaita pkgconf bash dbus sqlite3"
		;;
	OpenBSD)
		echo "    pkg_add rust gtk4 libadwaita pkgconf bash dbus sqlite3"
		;;
	DragonFly)
		echo "    pkg install rust gtk4 libadwaita pkgconf bash dbus sqlite3"
		;;
	*)
		echo "    Install: rust, gtk4, libadwaita, pkgconf, bash, dbus, sqlite3"
		;;
esac

echo ""
echo "==> Building Doumi..."
cd "${SCRIPT_DIR}"
cargo build --release

echo ""
echo "==> Installing binaries..."
RELEASE_DIR=$(find "${TARGET_DIR}" -maxdepth 3 -type f -name doumi 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
if [ -z "${RELEASE_DIR}" ]; then
	echo "ERROR: Could not find release directory"
	exit 1
fi

mkdir -p "${INSTALL_BIN}" "${INSTALL_DESKTOP}"
cp "${RELEASE_DIR}/doumi"  "${INSTALL_BIN}/doumi"
cp "${RELEASE_DIR}/doumid" "${INSTALL_BIN}/doumid"
if [ -f "${RELEASE_DIR}/doumi-gui" ]; then
	cp "${RELEASE_DIR}/doumi-gui" "${INSTALL_BIN}/doumi-gui"
fi

echo "==> Installing icons..."
for size in 16 32 48 64 128 256 512; do
	dir="${INSTALL_ICONS}/${size}x${size}/apps"
	mkdir -p "${dir}"
	src="${SCRIPT_DIR}/data/icons/doumi_${size}.png"
	if [ -f "${src}" ]; then
		cp "${src}" "${dir}/doumi.png"
	fi
done
if [ -f "${SCRIPT_DIR}/data/icons/doumi.svg" ]; then
	mkdir -p "${INSTALL_ICONS}/scalable/apps"
	cp "${SCRIPT_DIR}/data/icons/doumi.svg" "${INSTALL_ICONS}/scalable/apps/doumi.svg"
fi

echo "==> Installing .desktop entry..."
cp "${SCRIPT_DIR}/packaging/freebsd/doumi.desktop" "${INSTALL_DESKTOP}/doumi.desktop"
update-desktop-database "${INSTALL_DESKTOP}" 2>/dev/null || true

echo ""
echo "==> Installing rc.d service script..."
INSTALL_RCD=""
case "${OS}" in
	FreeBSD|DragonFly)
		INSTALL_RCD="${HOME}/.config/rc.d"
		mkdir -p "${INSTALL_RCD}"
		sed "s|%%PREFIX%%|${HOME}/.local|g" \
			"${SCRIPT_DIR}/packaging/freebsd/doumid" \
			> "${INSTALL_RCD}/doumid"
		chmod +x "${INSTALL_RCD}/doumid"
		echo "    Installed to ${INSTALL_RCD}/doumid"
		echo ""
		echo "    To start the daemon:"
		echo "      service doumid start"
		echo ""
		echo "    To auto-start on login, add to ~/.profile or ~/.xinitrc:"
		echo "      if [ -x ~/.config/rc.d/doumid ]; then"
		echo "          ~/.config/rc.d/doumid start"
		echo "      fi"
		;;
	NetBSD)
		echo "    NetBSD: Copy the rc.d script to /etc/rc.d/ or use ~/.config/rc.d/"
		echo "    See packaging/freebsd/doumid for the rc.d script template."
		;;
	OpenBSD)
		echo "    OpenBSD: Place a wrapper in /etc/rc.local or use a cron @reboot entry."
		echo "    See packaging/freebsd/doumid for reference."
		;;
esac

echo ""
echo "============================================"
echo "  Doumi installed to ${INSTALL_BIN}"
echo ""
echo "  Usage:"
echo "    doumi daemon start              # start background daemon"
echo "    doumi rules list                # list rules"
echo "    doumi gui                       # launch GUI rule editor"
echo "    service doumid start            # BSD rc.d service"
echo ""
echo "  Config:  ~/.config/doumi/"
echo "  Rules:   ~/.config/doumi/rules/"
echo "  Logs:    ~/.config/doumi/logs/"
echo "============================================"
