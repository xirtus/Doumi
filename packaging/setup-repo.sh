#!/usr/bin/env bash
# ─── One-time repo setup ────────────────────────────────────────────────────
# Run this ONCE from your laptop to bootstrap the apt/arch repositories.
# It generates a GPG key, exports it, and gives you the commands to wire
# everything together.
#
# After running this:
#   1. Add the GPG private key as GitHub Secret: APT_GPG_PRIVATE_KEY
#   2. Add the GPG public key as GitHub Secret:  APT_GPG_PUBLIC_KEY
#   3. Push — CI will sign the repo automatically.
#
# Requirements: gpg, dpkg-dev (for dpkg-scanpackages)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GPG_DIR="${PROJECT_DIR}/.gpg"
mkdir -p "$GPG_DIR"

echo "══════════════════════════════════════════════════"
echo "  Doumi Repository Setup"
echo "══════════════════════════════════════════════════"
echo ""

# ─── Step 1: GPG key ────────────────────────────────────────────────────────
read -rp "Email for GPG key (e.g. doumi@example.com): " GPG_EMAIL
read -rp "Full name for GPG key (e.g. Doumi Project): " GPG_NAME

if gpg --list-secret-keys --keyid-format LONG "$GPG_EMAIL" 2>/dev/null | grep -q sec; then
    echo "✓ GPG key for $GPG_EMAIL already exists"
else
    echo "→ Generating GPG key..."
    gpg --batch --gen-key << KEYGEN
    Key-Type: RSA
    Key-Length: 4096
    Name-Real: $GPG_NAME
    Name-Email: $GPG_EMAIL
    Expire-Date: 2y
    %no-protection
    %commit
KEYGEN
    echo "✓ GPG key generated"
fi

echo ""
echo "─── Add these secrets to your GitHub repo ───"
echo "    Settings → Secrets and variables → Actions → New repository secret"
echo ""

# Export private key (base64, for GitHub Secret)
echo "→ APT_GPG_PRIVATE_KEY:"
gpg --export-secret-key --armor "$GPG_EMAIL" | base64 -w0
echo ""
echo ""

# Export public key (armored, for the repo)
echo "→ APT_GPG_PUBLIC_KEY:"
gpg --export --armor "$GPG_EMAIL"
echo ""

gpg --export "$GPG_EMAIL" > "${GPG_DIR}/doumi.gpg"
echo "✓ Public key saved to .gpg/doumi.gpg"

echo ""
echo "══════════════════════════════════════════════════"
echo "  Next steps:"
echo ""
echo "  1. Copy the secrets above into GitHub"
echo "  2. Push a tag:  git tag v0.1.0 && git push --tags"
echo "  3. Enable GitHub Pages in repo Settings → Pages"
echo "     Source: Deploy from a branch → gh-pages → / (root)"
echo "  4. Users can then:"
echo ""
echo "     # Debian/Ubuntu"
echo "     curl -fsSL https://USER.github.io/REPO/debian/gpg.key | \\"
echo "       sudo gpg --dearmor -o /usr/share/keyrings/doumi-archive-keyring.gpg"
echo "     echo \"deb [signed-by=/usr/share/keyrings/doumi-archive-keyring.gpg] \\"
echo "       https://USER.github.io/REPO/debian stable main\" | \\"
echo "       sudo tee /etc/apt/sources.list.d/doumi.list"
echo "     sudo apt update && sudo apt install doumi"
echo ""
echo "     # Arch"
echo "     # Add to /etc/pacman.conf:"
echo "     [doumi]"
echo "     Server = https://USER.github.io/REPO/arch/"
echo "     sudo pacman -Syu doumi"
echo ""
echo "══════════════════════════════════════════════════"
