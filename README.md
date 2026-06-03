<img width="784" height="657" alt="doumi" src="https://github.com/user-attachments/assets/b6247595-dbf4-42ec-a4a6-3cc3e2ebf3e2" />
<div align="center">

# Doumi

**A bright, fast, open-source file automation assistant for people who want their desktop to clean itself.**

[![Linux](https://img.shields.io/badge/Linux-Rust%20AppImage-2EA44F?style=for-the-badge&logo=linux&logoColor=white)](#linux)
[![Windows](https://img.shields.io/badge/Windows-Rust%20MSVC-0078D6?style=for-the-badge&logo=windows&logoColor=white)](Windows/)
[![BSD](https://img.shields.io/badge/BSD-Rust%20Port-AB2B28?style=for-the-badge&logo=freebsd&logoColor=white)](#freebsd)
[![macOS](https://img.shields.io/badge/macOS-Swift%20Project-147EFB?style=for-the-badge&logo=apple&logoColor=white)](Mac/)
[![Open Source](https://img.shields.io/badge/Open%20Source-Free%20Forever-FFB000?style=for-the-badge)](LICENSE)

**Rules you can read. Automation you can trust. A cleaner home folder without a closed, proprietary rules box.**

</div>

---

**Doumi** watches your folders and automatically organizes files using rules
you define — like Hazel for macOS, but native on Linux and BSD.  Move, rename,
tag, archive, or run scripts on files that match conditions like extension,
name pattern, date, size, or file kind.

Built in Rust.  Real-time watcher (inotify / kqueue), cron scheduler,
GTK4 GUI, and CLI.

---

## Installation

> **Note:** these URLs use `xirtus` as a placeholder. Replace it with the
> GitHub username or organization where this repo is hosted. If you're reading this
> on a fork, the repo owner already set this up.

### 🐧 Debian / Ubuntu / Mint / Pop!_OS

```bash
# 1. Add the Doumi repository (one-time)
curl -fsSL https://xirtus.github.io/doumi/debian/gpg.key | \
  sudo gpg --dearmor -o /usr/share/keyrings/doumi-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/doumi-archive-keyring.gpg] \
  https://xirtus.github.io/doumi/debian stable main" | \
  sudo tee /etc/apt/sources.list.d/doumi.list

# 2. Install
sudo apt update
sudo apt install doumi
```

Once the repo is added, **future updates arrive with your normal system updates.**

#### Alternative: grab the `.deb` directly from GitHub Releases

```bash
curl -LO https://github.com/xirtus/doumi/releases/latest/download/doumi_amd64.deb
sudo apt install ./doumi_amd64.deb
```

### 🎩 Arch Linux / Manjaro / EndeavourOS

```bash
# From the AUR (recommended)
yay -S doumi
# or
paru -S doumi
```

Or add the custom repo for direct `pacman -S doumi`:

```bash
curl -fsSL https://xirtus.github.io/doumi/arch/gpg.key | sudo pacman-key --add -
sudo pacman-key --lsign-key doumi@example.com
echo -e "\n[doumi]\nServer = https://xirtus.github.io/doumi/arch/\n" | sudo tee -a /etc/pacman.conf
sudo pacman -Syu doumi
```

### 🐳 Build from source

```bash
git clone https://github.com/xirtus/doumi.git
cd doumi
cargo build --release
./target/release/doumi --help
```

**Build deps:** `cargo rustc gtk4 libadwaita`

### 😈 FreeBSD

#### From ports (recommended)

```bash
cd /usr/ports/sysutils/doumi
make install clean
```

Or use `pkg` once the package is available:

```bash
pkg install doumi
```

#### Quick install script

```bash
git clone https://github.com/xirtus/doumi.git
cd doumi
./install-bsd.sh
```

#### rc.d service

```bash
# Start the daemon
service doumid start

# Auto-start on boot
sysrc doumid_enable=YES

# Optional: run in dry-run mode
sysrc doumid_dry_run=YES
```

### 🪟 Windows

**Pre-built:** Download `doumi-windows-v*.zip` from
**[GitHub Releases](https://github.com/xirtus/doumi/releases/latest)**,
extract, and run `install.ps1`.

**From source:**

```powershell
git clone https://github.com/xirtus/doumi.git
cd doumi\Windows
.\build.ps1
.\install.ps1
```

**Requires:** Rust with MSVC toolchain.  See [Windows/README.md](Windows/README.md)
for detailed instructions, service setup, and GUI notes.

### 😈 NetBSD / OpenBSD / DragonFly BSD

Build from source with `cargo build --release`.  See `packaging/freebsd/`
for service script templates and adapt to your system's init system.
The `install-bsd.sh` script provides a guided setup.

---

## Publishing your own repo (maintainers)

If you forked this, here's how to make the install commands above work:

### 1. Push to GitHub and enable Pages

Create a repo named `doumi` on GitHub, push this code to `main`, then:

> **Settings → Pages → Source:** `GitHub Actions`  *(or `Deploy from a branch → gh-pages → / (root)`)*

### 2. (Optional) Sign packages with GPG

```bash
./packaging/setup-repo.sh
```

This generates a GPG key and prints the secrets to paste into:
**Settings → Secrets and variables → Actions → New repository secret**

- `APT_GPG_PRIVATE_KEY` — for automatic `Release` signing
- `APT_GPG_PUBLIC_KEY`  — for the `gpg.key` that users download

*If you skip this step, the apt repo works unsigned (users just get a warning).*

### 3. Cut a release

```bash
git tag v0.1.0
git push --tags
```

The `release.yml` workflow builds the `.deb` and Arch package, publishes them to
**GitHub Releases**, and deploys apt + Arch repositories to **GitHub Pages**.

After the workflow completes, the `apt-get install` and `pacman -S` commands
above will work for your users.

### 4. Submit to AUR (optional)

Copy `packaging/arch/PKGBUILD` and `packaging/arch/doumi.install` to a new AUR
submission. Once accepted, `yay -S doumi` will work for all Arch users.

---

## Quick start

```bash
# Fire up the background daemon
doumi daemon start

# Create your first rule — sort Downloads by file kind
doumi rules add "Sort Downloads" -f ~/Downloads

# Edit it
doumi rules edit <rule-id>

# Or use the visual editor
doumi gui

# Everything that happens is logged
doumi logs

# Auto-start daemon on login
systemctl --user enable --now doumi

# On BSD:
service doumid start
```

---

## How rules work

A rule says: **if** a file matching certain conditions appears in a folder,
**then** perform actions on it.

```
Rule: "Archive old PDFs"

  Watch:    ~/Downloads
  Trigger:  file added · every Sunday at 3am

  IF  (all of)
      ├─ File extension  is  pdf
      ├─ Date added      is older than  4 weeks
      └─ Size            is greater than  1 MB

  THEN
      ├─ Move to  ~/Archive/PDF/{year}/{month}
      └─ Notify   "Archived {name}"
```

Rule files are plain JSON in `~/.config/doumi/rules/`.  The GUI gives you a
Hazel-like madlib editor so you never need to touch JSON.

### Available conditions

| Category | Conditions |
|---|---|
| **Name** | is, contains, starts_with, ends_with, matches (regex) |
| **Extension** | is_one_of, is_not_one_of |
| **Date** | added, created, modified — is_before, is_after, is_in_the_last |
| **Size** | greater_than, less_than |
| **Kind** | is_one_of (document, image, video, audio, archive, code) |
| **Group** | all, any, none — nest conditions arbitrarily |

### Available actions

| Action | Description |
|---|---|
| **move** | Move file to a destination with template variables |
| **copy** | Copy file to a destination |
| **rename** | Rename using template patterns |
| **trash** | Send file to trash |
| **delete** | Permanently delete |
| **notify** | Send desktop notification |
| **run** | Execute a shell command |
| **archive** | Compress into .zip / .tar.gz / .tar.bz2 |
| **set_xattr** | Set extended file attributes |
| **tag** | Add a virtual tag |

**Template variables:** `{name}` `{ext}` `{kind}` `{year}` `{month}` `{day}` `{date}` `{uuid}` `{basename}` `{size}`

---

## Architecture

```
┌─────────────┐     IPC (Unix socket)      ┌──────────────┐
│  doumi CLI  │◄──────────────────────────►│   doumid     │
│  ─────────  │   status, reload, logs,    │   ────────   │
│  rules add  │   preview, run             │   inotify /  │
│  rules list │                            │   kqueue     │
│  daemon *   │                            │   cron       │
│  logs       │                            │   engine     │
│  config     │                            │   sqlite db  │
└──────┬──────┘                                   │
       │ launches                                 │
       ▼                                          ▼
┌──────────────┐                         ┌────────────────┐
│  doumi-gui   │                         │  ~/.config/    │
│  ─────────   │                         │    doumi/      │
│  GTK4 +      │                         │    ├─ rules/   │
│  libadwaita  │                         │    ├─ db.sqlite│
│  rule editor │                         │    └─ config   │
└──────────────┘                         └────────────────┘
```

- **doumi** — CLI; talks to daemon over Unix socket (Linux/BSD/macOS) or local TCP (Windows), edits rule files
- **doumid** — background daemon; watches files (inotify on Linux, kqueue on BSD, ReadDirectoryChangesW on Windows), evaluates rules, executes actions
- **doumi-gui** — GTK4 visual rule editor
- **doumi-core** — shared library: rule engine, conditions, actions, config loading

---

## Safety

Doumi refuses to touch:

- System directories (`/bin`, `/boot`, `/dev`, `/etc`, `/lib*`, `/proc`, `/run`,
  `/sbin`, `/sys`, `/tmp`, `/usr`, `/var`)
- Project roots (directories containing `.git`, `Cargo.toml`, `package.json`,
  `Makefile`, `CMakeLists.txt`, `pom.xml`, `setup.py`)
- Files with multiple hardlinks
- Symlinks pointing outside the watched folder
- Hidden files / dot-prefixed entries (configurable)

Use `--dry-run` for any command to preview without touching files.

---

## Configuration

`~/.config/doumi/config.json`:

```json
{
  "ipc_socket": "~/.local/share/doumi/doumi.sock",
  "rules_dir": "~/.config/doumi/rules",
  "db_path": "~/.local/share/doumi/events.db",
  "safety": {
    "protect_home_dir": true,
    "protect_system_dirs": true,
    "protect_project_roots": true,
    "protect_multiple_hardlinks": true,
    "protect_symlinks_external": true,
    "protect_hidden_files": true
  }
}
```

---

## Contributing

```bash
cargo test
cargo fmt -- --check
cargo clippy -- -D warnings
```

Issues and PRs welcome.

---

## License

MIT — see [LICENSE](LICENSE).
