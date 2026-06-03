<div align="center">

# Doumi

**A bright, fast, open-source file automation assistant for people who want their desktop to clean itself.**

[![Linux](https://img.shields.io/badge/Linux-Rust%20AppImage-2EA44F?style=for-the-badge&logo=linux&logoColor=white)](Linux/)
[![macOS](https://img.shields.io/badge/macOS-Swift%20Project-147EFB?style=for-the-badge&logo=apple&logoColor=white)](Mac/)
[![Open Source](https://img.shields.io/badge/Open%20Source-Free%20Forever-FFB000?style=for-the-badge)](Mac/LICENSE)

**Rules you can read. Automation you can trust. A cleaner home folder without a closed, proprietary rules box.**

</div>

---

## Why Doumi Exists

Doumi is a file organizer with a simple promise: your computer should take care of repetitive cleanup without hiding the logic from you.

It watches folders, matches files with clear rules, and runs actions like move, copy, trash, archive, compress, notify, and shell commands. Your rules live as normal files, so you can inspect them, version them, share them, and keep control.

## Pick Your Platform

| Platform | What is inside | Start here |
|---|---|---|
| Linux | Pure Rust app, GUI, daemon, CLI, AppImage, installer, scripts, examples | [`Linux/`](Linux/) |
| macOS | Original Swift macOS project, CLI, menu bar app, examples | [`Mac/`](Mac/) |

## Install On Linux

Fast AppImage install:

```bash
mkdir -p "$HOME/.local/bin"
curl -L https://github.com/xirtus/Doumi/raw/main/Linux/Doumi-Linux-x86_64.AppImage -o "$HOME/.local/bin/Doumi.AppImage"
chmod +x "$HOME/.local/bin/Doumi.AppImage"
"$HOME/.local/bin/Doumi.AppImage"
```

Full source install:

```bash
tmpdir="$(mktemp -d)"
curl -L https://github.com/xirtus/Doumi/raw/main/Linux/Doumi-Linux-rust-source.tar.gz -o "$tmpdir/Doumi-Linux-rust-source.tar.gz"
tar -xzf "$tmpdir/Doumi-Linux-rust-source.tar.gz" -C "$tmpdir"
cd "$tmpdir"
./install.sh
```

## What Makes It Good

| Feature | Why it matters |
|---|---|
| Plain rule files | No lock-in, no mystery database, no hidden automation state |
| Rust Linux build | Fast native daemon, CLI, and GTK/libadwaita GUI |
| Swift macOS build | Native Mac implementation with the original project preserved |
| AppImage release | Download, chmod, run |
| Source installer | Builds and installs the Linux daemon, desktop entry, icons, and user service |
| Examples included | Start from real rules instead of a blank screen |
| Checksums included | Verify what you download |

## Repository Layout

```text
Doumi/
+-- Linux/
|   +-- Doumi-Linux-x86_64.AppImage
|   +-- Doumi-Linux-rust-source.tar.gz
|   +-- README.md
|   +-- install.sh
|   +-- scripts/
|   +-- examples/
+-- Mac/
    +-- README.md
    +-- Package.swift
    +-- Sources/
    +-- scripts/
    +-- examples/
```

## Project Spirit

Doumi is for the person who wants a Downloads folder that does not rot, a Desktop that does not turn into a junk drawer, and automation that remains legible after six months. It is practical, local-first, and built around rules you can actually understand.

For Linux details, scripts, and examples, open [`Linux/README.md`](Linux/README.md).  
For the original macOS documentation, open [`Mac/README.md`](Mac/README.md).
