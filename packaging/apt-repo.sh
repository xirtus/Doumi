#!/usr/bin/env bash
# ─── Manage the apt repository on GitHub Pages ──────────────────────────────
#
# This script is used by CI, but you can also run it locally to preview.
#
# Usage:
#   ./packaging/apt-repo.sh init          # Create repo structure
#   ./packaging/apt-repo.sh add ./pkg.deb # Add a .deb to the repo
#   ./packaging/apt-repo.sh sign          # Sign the Release file
#   ./packaging/apt-repo.sh deploy        # Push to gh-pages branch
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="${PROJECT_DIR}/apt-repo"
GPG_KEY="${GPG_KEY:-doumi@example.com}"
REPO_USER="${GITHUB_REPOSITORY_OWNER:-doumi}"
REPO_NAME="${GITHUB_REPOSITORY##*/}"
REPO_NAME="${REPO_NAME:-doumi}"

init() {
    rm -rf "$REPO_DIR"
    mkdir -p "$REPO_DIR/dists/stable/main/binary-amd64"
    mkdir -p "$REPO_DIR/pool/main"
    echo "apt-repo/ initialized"
}

add_deb() {
    local deb="$1"
    local name
    name=$(basename "$deb")
    cp "$deb" "$REPO_DIR/pool/main/$name"

    cd "$REPO_DIR"
    dpkg-scanpackages --multiversion pool/ > dists/stable/main/binary-amd64/Packages
    gzip -kf dists/stable/main/binary-amd64/Packages

    # Create Release file
    cat > dists/stable/Release << RELEASE
Origin: Doumi
Label: Doumi
Suite: stable
Codename: stable
Date: $(date -Ru)
Architectures: amd64
Components: main
Description: Doumi — intelligent file organizer for Linux
SHA256:
$(cd dists/stable && sha256sum main/binary-amd64/Packages main/binary-amd64/Packages.gz | awk '{print " " $1 " " $3 " " $2}')
RELEASE
    echo "Added $name to apt repo"
}

sign() {
    cd "$REPO_DIR"
    if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
        echo "$GPG_PRIVATE_KEY" | base64 -d | gpg --batch --import
    fi
    gpg --batch --yes --default-key "$GPG_KEY" \
        --detach-sign --armor \
        -o dists/stable/Release.gpg \
        dists/stable/Release
    gpg --batch --yes --default-key "$GPG_KEY" \
        --detach-sign --armor --clearsign \
        -o dists/stable/InRelease \
        dists/stable/Release
    echo "Signed Release with $GPG_KEY"
}

deploy() {
    cd "$REPO_DIR"
    # Export public key for users
    gpg --export --armor "$GPG_KEY" > gpg.key

    # If we're in CI, use the actions/gh-pages action instead
    if [ -n "${CI:-}" ]; then
        echo "Running in CI — use peaceiris/actions-gh-pages to deploy"
        return
    fi

    # Local deploy to gh-pages branch
    git init -b gh-pages
    git add -A
    git commit -m "Update apt repo" || true
    git push -f "git@github.com:${REPO_USER}/${REPO_NAME}.git" gh-pages:gh-pages
    echo "Deployed to GitHub Pages"
}

case "${1:-}" in
    init)    init ;;
    add)     add_deb "$2" ;;
    sign)    sign ;;
    deploy)  deploy ;;
    all)
        init
        add_deb "$2"
        sign
        # deploy is manual (needs push access)
        echo "Repo ready in apt-repo/. Deploy with: $0 deploy"
        ;;
    *)
        echo "Usage: $0 {init|add <pkg.deb>|sign|deploy|all <pkg.deb>}"
        exit 1
        ;;
esac
