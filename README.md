# Doumi

Doumi is split by platform:

- `Mac/` contains the original Swift macOS project.
- `Linux/` contains the pure Rust Linux build, installer, AppImage, and checksums.

## Linux Install

Fast path with the AppImage:

```bash
mkdir -p "$HOME/.local/bin"
curl -L https://github.com/xirtus/Doumi/raw/main/Linux/Doumi-Linux-x86_64.AppImage -o "$HOME/.local/bin/Doumi.AppImage"
chmod +x "$HOME/.local/bin/Doumi.AppImage"
"$HOME/.local/bin/Doumi.AppImage"
```

Install from the Rust source bundle:

```bash
tmpdir="$(mktemp -d)"
curl -L https://github.com/xirtus/Doumi/raw/main/Linux/Doumi-Linux-rust-source.tar.gz -o "$tmpdir/Doumi-Linux-rust-source.tar.gz"
tar -xzf "$tmpdir/Doumi-Linux-rust-source.tar.gz" -C "$tmpdir"
cd "$tmpdir"
./install.sh
```

Verify downloads:

```bash
mkdir -p doumi-downloads
cd doumi-downloads
curl -L https://github.com/xirtus/Doumi/raw/main/Linux/SHA256SUMS -o SHA256SUMS
curl -L https://github.com/xirtus/Doumi/raw/main/Linux/Doumi-Linux-x86_64.AppImage -o Doumi-Linux-x86_64.AppImage
curl -L https://github.com/xirtus/Doumi/raw/main/Linux/Doumi-Linux-rust-source.tar.gz -o Doumi-Linux-rust-source.tar.gz
curl -L https://github.com/xirtus/Doumi/raw/main/Linux/install.sh -o install.sh
sha256sum -c SHA256SUMS
```

## macOS

The Swift macOS project lives in `Mac/`.
