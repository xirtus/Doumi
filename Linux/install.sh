#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${CARGO_TARGET_DIR:-$SCRIPT_DIR/target}"
INSTALL_BIN="$HOME/.local/bin"
INSTALL_SYSTEMD="$HOME/.config/systemd/user"
INSTALL_DESKTOP="$HOME/.local/share/applications"
INSTALL_ICONS="$HOME/.local/share/icons/hicolor"

mkdir -p "$INSTALL_BIN" "$INSTALL_SYSTEMD" "$INSTALL_DESKTOP"

echo "Building Doumi v2 (Rust)..."
cd "$SCRIPT_DIR"
cargo build --release

echo "Installing binaries..."
# Release dir varies by target triple; find it
RELEASE_DIR=$(find "$TARGET_DIR" -maxdepth 3 -type f -name doumi | head -1 | xargs dirname)
cp "$RELEASE_DIR/doumi"  "$INSTALL_BIN/doumi"
cp "$RELEASE_DIR/doumid" "$INSTALL_BIN/doumid"
if [ -f "$RELEASE_DIR/doumi-gui" ]; then
    cp "$RELEASE_DIR/doumi-gui" "$INSTALL_BIN/doumi-gui"
fi

echo "Installing icons..."
for size in 16 32 48 64 128 256 512; do
    dir="$INSTALL_ICONS/${size}x${size}/apps"
    mkdir -p "$dir"
    src="$SCRIPT_DIR/data/icons/doumi_${size}.png"
    if [ -f "$src" ]; then
        cp "$src" "$dir/doumi.png"
    fi
done
if [ -f "$SCRIPT_DIR/data/icons/doumi.svg" ]; then
    mkdir -p "$INSTALL_ICONS/scalable/apps"
    cp "$SCRIPT_DIR/data/icons/doumi.svg" "$INSTALL_ICONS/scalable/apps/doumi.svg"
fi
gtk-update-icon-cache -f -t "$INSTALL_ICONS" 2>/dev/null || true
xdg-icon-resource forceupdate --mode user 2>/dev/null || true

echo "Installing .desktop entry..."
cat > "$INSTALL_DESKTOP/doumi.desktop" << DESKTOP
[Desktop Entry]
Name=Doumi
GenericName=File Organizer
Comment=Intelligent file organization rules for Linux
Exec=$INSTALL_BIN/doumi gui
Icon=doumi
Terminal=false
Type=Application
Categories=Utility;FileManager;
Keywords=file;organize;automate;rules;hazel;
StartupWMClass=doumi
Actions=StartDaemon;StopDaemon;

[Desktop Action StartDaemon]
Name=Start Daemon
Exec=$INSTALL_BIN/doumi daemon start

[Desktop Action StopDaemon]
Name=Stop Daemon
Exec=$INSTALL_BIN/doumi daemon stop
DESKTOP

update-desktop-database "$INSTALL_DESKTOP" 2>/dev/null || true

echo "Installing systemd unit..."
cat > "$INSTALL_SYSTEMD/doumi.service" << SERVICE
[Unit]
Description=Doumi file organizer daemon
After=graphical-session.target

[Service]
Type=simple
ExecStart=$INSTALL_BIN/doumid
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=doumid

[Install]
WantedBy=default.target
SERVICE
systemctl --user daemon-reload 2>/dev/null || true

echo ""
echo "Doumi v2 installed to $INSTALL_BIN"
echo ""
echo "Usage:"
echo "  doumi daemon start          # start background daemon"
echo "  doumi rules list            # list rules"
echo "  systemctl --user enable --now doumi   # auto-start on login"
echo ""
echo "The 'Doumi' entry is now in your application launcher."
