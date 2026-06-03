# Doumi for Windows

<img width="784" height="657" alt="doumi" src="https://github.com/user-attachments/assets/b6247595-dbf4-42ec-a4a6-3cc3e2ebf3e2" />

**Doumi** watches your folders and automatically organizes files using rules
you define — now native on Windows. Move, rename, tag, archive, or run scripts
on files that match conditions like extension, name pattern, date, size, or
file kind.

Built in Rust. Real-time watcher (ReadDirectoryChangesW), cron scheduler,
optional GTK4 GUI, and CLI.

---

## Quick Start

### Option A: Download pre-built (recommended)

1. Go to **[GitHub Releases](https://github.com/xirtus/doumi/releases/latest)**
2. Download `doumi-windows-v*.zip`
3. Extract anywhere, then right-click `install.ps1` → **Run with PowerShell**

The installer copies the binaries to `%LOCALAPPDATA%\Programs\Doumi\` and adds
them to your PATH.

```powershell
# Fire up the background daemon
doumi daemon start

# Create your first rule — sort Downloads by file kind
doumi rules add "Sort Downloads" -f %USERPROFILE%\Downloads

# Preview what the rule would do
doumi rules preview --rule-id <rule-id>

# Auto-start daemon on login
& "$env:LOCALAPPDATA\Programs\Doumi\doumi-service.ps1" install
```

### Option B: Build from source

#### 1. Install Rust (if needed)

Open **PowerShell as Administrator** and run:

```powershell
winget install Rustlang.Rustup
```

Or download from https://rustup.rs.

#### 2. Clone and build

```powershell
git clone https://github.com/xirtus/doumi.git
cd doumi\Windows
.\build.ps1
```

This produces:
- `target\release\doumi.exe` — CLI
- `target\release\doumid.exe` — background daemon
- `target\release\doumi-gui.exe` — GUI (optional, requires GTK4)

#### 3. Install

```powershell
.\install.ps1
```

This installs to `%LOCALAPPDATA%\Programs\Doumi\` and adds it to your PATH.

#### 4. Run

```powershell
doumi daemon start
doumi rules add "Sort Downloads" -f %USERPROFILE%\Downloads
doumi rules preview --rule-id <rule-id>
doumi logs
& "$env:LOCALAPPDATA\Programs\Doumi\doumi-service.ps1" install
```

---

## Architecture (Windows)

```
┌─────────────┐     IPC (TCP localhost)      ┌──────────────┐
│  doumi CLI  │◄────────────────────────────►│   doumid     │
│  ─────────  │   status, reload, logs,      │   ────────   │
│  rules add  │   preview, run               │   ReadDir-   │
│  rules list │                              │   ChangesW   │
│  daemon *   │                              │   cron       │
│  logs       │                              │   engine     │
│  config     │                              │   sqlite db  │
└──────┬──────┘                                    │
       │ launches                                  │
       ▼                                           ▼
┌──────────────┐                         ┌─────────────────┐
│  doumi-gui   │                         │  %APPDATA%\     │
│  ─────────   │                         │    doumi\       │
│  GTK4 +      │                         │    ├─ rules\    │
│  libadwaita  │                         │    ├─ db.sqlite │
│  rule editor │                         │    └─ settings  │
└──────────────┘                         └─────────────────┘
```

**Key differences from Linux/BSD:**
- **IPC:** Local TCP (127.0.0.1) instead of Unix domain sockets
- **File watching:** `ReadDirectoryChangesW` (via `notify` crate) instead of `inotify`/`kqueue`
- **Service:** Windows scheduled task instead of systemd/rc.d
- **Permissions:** `set_permissions` action is not available (Unix-only)
- **Tagging:** Sidecar `.doumi_tags.json` files instead of xattrs
- **Daemon:** Background process with `CREATE_NO_WINDOW` flag

---

## Building from source

### Prerequisites

- **Rust** 1.80+ with MSVC toolchain (`rustup default stable-msvc`)
- **Git** for cloning

### Build options

```powershell
# Release build (optimized)
.\build.ps1

# Debug build
.\build.ps1 -Debug

# Build without GUI (skip GTK4 dependency)
.\build.ps1 -NoGui

# Cross-compile notes:
# Install target: rustup target add x86_64-pc-windows-msvc
# Build will use MSVC by default on Windows
```

---

## Running as a Windows Service

Doumi can run as a **scheduled task** that starts at login:

```powershell
# Install the scheduled task (starts on login)
.\doumi-service.ps1 install

# With dry-run mode (preview, no files touched)
.\doumi-service.ps1 install -DryRun

# Remove the scheduled task
.\doumi-service.ps1 uninstall

# Check status
.\doumi-service.ps1 status
```

---

## How rules work

Rule files are plain JSON in `%APPDATA%\doumi\rules\`. Same format as the
Linux/BSD version.

Quick example — archive old downloads by extension:

```json
{
  "id": "archive-downloads",
  "name": "Archive Downloads",
  "enabled": true,
  "priority": 0,
  "folders": [{
    "path": "C:\\Users\\You\\Downloads",
    "recursive": false
  }],
  "triggers": {
    "on_add": false,
    "schedule": "0 3 * * *"
  },
  "conditions": {
    "type": "extension",
    "operator": "is_one_of",
    "value": ["zip", "msi", "exe", "tar.gz", "7z", "rar"]
  },
  "actions": [{
    "type": "move",
    "destination": "C:\\Users\\You\\Archive\\{ext}\\{year}-{month}",
    "on_conflict": "rename",
    "create_parents": true
  }]
}
```

---

## Configuration

`%APPDATA%\doumi\settings.json`:

```json
{
  "log_level": "INFO",
  "log_actions": true,
  "max_log_entries": 10000,
  "dry_run": false,
  "ipc_socket": "%APPDATA%\\doumi\\doumi.sock",
  "scan_on_start": true
}
```

---

## Safety (same as Linux/BSD)

Doumi refuses to touch:
- System directories (`C:\Windows`, `C:\Program Files`, `C:\Program Files (x86)`)
- Project roots (directories containing `.git`, `Cargo.toml`, `package.json`, etc.)
- Hidden files / dot-prefixed entries (configurable)

Use `--dry-run` for any command to preview without touching files.

---

## Contributing

```powershell
cargo test
cargo fmt -- --check
cargo clippy -- -D warnings
```

Issues and PRs welcome.

---

## License

MIT — see [../LICENSE](../LICENSE).
