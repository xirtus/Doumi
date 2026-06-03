# Doumi For Linux

This folder contains the pure Rust Linux edition of Doumi: a native CLI, daemon, and GTK/libadwaita GUI for file automation.

## Contents

| Path | Purpose |
|---|---|
| `Doumi-Linux-x86_64.AppImage` | Portable Linux GUI build |
| `Doumi-Linux-rust-source.tar.gz` | Source bundle for building and installing locally |
| `install.sh` | Installer from the source bundle |
| `SHA256SUMS` | Checksums for release artifacts |
| `scripts/` | Helper scripts for installing and verifying downloads |
| `examples/` | Ready-to-adapt rule examples |

## AppImage Install

```bash
mkdir -p "$HOME/.local/bin"
curl -L https://github.com/xirtus/Doumi/raw/main/Linux/Doumi-Linux-x86_64.AppImage -o "$HOME/.local/bin/Doumi.AppImage"
chmod +x "$HOME/.local/bin/Doumi.AppImage"
"$HOME/.local/bin/Doumi.AppImage"
```

Or from this folder after cloning:

```bash
./scripts/install-appimage.sh
```

## Source Install

```bash
tmpdir="$(mktemp -d)"
curl -L https://github.com/xirtus/Doumi/raw/main/Linux/Doumi-Linux-rust-source.tar.gz -o "$tmpdir/Doumi-Linux-rust-source.tar.gz"
tar -xzf "$tmpdir/Doumi-Linux-rust-source.tar.gz" -C "$tmpdir"
cd "$tmpdir"
./install.sh
```

Or from this folder after cloning:

```bash
./scripts/install-from-source.sh
```

The source installer builds the Rust workspace and installs:

- `doumi`
- `doumid`
- `doumi-gui`
- desktop launcher
- app icons
- user systemd service

## Verify Artifacts

From this folder:

```bash
./scripts/verify-artifacts.sh
```

Manual verification:

```bash
sha256sum -c SHA256SUMS
```

## Examples

Rule examples live in `examples/rules/`.

| Example | What it does |
|---|---|
| `archive_downloads.json` | Archives older Downloads files on a schedule |
| `cleanup_temp.json` | Cleans temporary files |
| `compress_large_files.json` | Compresses large files |
| `organize_photos.json` | Sorts photos |
| `sort_documents.json` | Sorts documents |

Copy an example into your Doumi rule directory and edit paths before enabling it.

```bash
mkdir -p "$HOME/.config/doumi/rules"
cp examples/rules/archive_downloads.json "$HOME/.config/doumi/rules/"
```

## Useful Commands

```bash
doumi daemon start
doumi daemon stop
doumi rules list
systemctl --user enable --now doumi
```
