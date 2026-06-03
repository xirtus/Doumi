# Doumi 도우미

Open-source file automation daemon for macOS — a better, free alternative to Hazel.

Rules live in plain YAML files you can edit in any text editor, version-control with git, or share with anyone.

## Why Doumi over Hazel?

| | Hazel | Doumi |
|---|---|---|
| Price | $42 | Free |
| Rule format | Proprietary GUI | YAML files |
| Version control | ✗ | ✓ (just `git add config.yaml`) |
| Share rules | Hard | Copy a file |
| Dry-run mode | ✗ | ✓ `--dry-run` |
| Shell scripts | Limited | Full shell access |
| Headless / server | ✗ | ✓ |
| Open source | ✗ | ✓ |

## Install

### Homebrew Cask (recommended)

```bash
brew install --cask xirtus/doumi/doumi
```

That drops `Doumi.app` into `/Applications` and makes the `doumi` CLI available.

### Build from source

```bash
# Requires Xcode Command Line Tools
cd /path/to/Doumi
swift build -c release
sudo cp .build/release/doumi /usr/local/bin/

# Create default config dir
mkdir -p ~/.config/doumi
cp examples/config.yaml ~/.config/doumi/config.yaml
```

## Quick start

1. Edit `~/.config/doumi/config.yaml`
2. Run `doumi validate` to check for errors
3. Run `doumi run --dry-run` to preview what would happen
4. Run `doumi watch` to start in the foreground
5. Run `doumi install` to auto-start at login

## Commands

```
doumi watch          Watch directories in the foreground (Ctrl+C to stop)
doumi run            One-shot: apply rules to existing files
doumi run --dry-run  Preview without making any changes
doumi validate       Check config file for errors
doumi install        Install LaunchAgent (auto-start at login)
doumi uninstall      Remove LaunchAgent
doumi --help         Show all options
doumi --version      Show version
```

## Config format

```yaml
global:
  dry_run: false
  log_level: info   # debug | info | warn | error

watch:
  - name: Desktop Cleanup
    path: ~/Desktop
    recursive: false    # set true to watch subdirectories too
    rules:

      - name: Sort Screenshots
        match: all       # all | any  (default: all)
        stop: true       # stop checking further rules after this matches (default: true)
        conditions:
          - type: name
            starts_with: "Screenshot"
          - type: extension
            one_of: [png, jpg]
        actions:
          - type: move
            to: ~/Pictures/Screenshots/{year}-{month}/
```

## Condition types

### `name` — match the filename
```yaml
- type: name
  glob: "Screenshot*"       # shell glob (* and ?)
  not_glob: "._*"           # must NOT match this glob
  regex: "^IMG_\d+"         # regular expression
  is: "untitled.txt"        # exact match
  contains: "invoice"
  starts_with: "2024"
  ends_with: "_final"
```

### `extension` — match file extension
```yaml
- type: extension
  is: pdf
  one_of: [jpg, jpeg, png, gif, webp]
  not: tmp
  not_one_of: [dmg, pkg]
```

### `size` — file size
```yaml
- type: size
  gt: 100mb     # greater than
  lt: 2gb       # less than
  gte: 1kb      # greater than or equal
  lte: 500mb    # less than or equal
# units: b kb mb gb tb
```

### `age` — file age
```yaml
- type: age
  older_than: 30d    # older than 30 days
  newer_than: 5s     # newer than 5 seconds
  basis: modified    # modified (default) | created
# units: s m h d w mo y
```

### `kind` — file type
```yaml
- type: kind
  is: file        # file | directory | symlink
```

### `script` — arbitrary shell condition
```yaml
- type: script
  run: "exiftool -q -q \"$DOUMI_FILE\" 2>/dev/null"
# Matches if the command exits 0.
# Env vars: DOUMI_FILE, DOUMI_NAME, DOUMI_EXT
```

### `tags` — macOS Finder tags
```yaml
- type: tags
  one_of: [Red, Important]
```

## Action types

### `move` / `copy`
```yaml
- type: move
  to: ~/Documents/{year}/{month}/
  create_dirs: true           # create destination dirs (default: true)
  on_conflict: rename         # rename | skip | overwrite | error (default: rename)
```

### `rename`
```yaml
- type: rename
  to: "{date}_{name}.{ext}"
```

### `trash` / `delete`
```yaml
- type: trash    # moves to Trash (recoverable)
- type: delete   # permanent delete
```

### `run` — shell command
```yaml
- type: run
  command: "tag --add 'Processed' \"$DOUMI_FILE\""
# Template vars and env vars (DOUMI_FILE, DOUMI_NAME, DOUMI_EXT) are available
```

### `notify` — macOS notification
```yaml
- type: notify
  title: "Doumi"              # optional, defaults to "Doumi"
  message: "Moved {filename}"
```

### `log`
```yaml
- type: log
  message: "Processed: {filename}"   # optional
```

### `open`
```yaml
- type: open
  with: "Preview"    # optional app name; omit to use default app
```

## Template variables

Available in `to:`, `message:`, `command:`, and `rename.to:`:

| Variable | Description |
|---|---|
| `{filename}` | Full filename (e.g. `report.pdf`) |
| `{name}` / `{stem}` | Filename without extension |
| `{ext}` | Extension without dot |
| `{year}` | 4-digit year from modification date |
| `{month}` | 2-digit month |
| `{day}` | 2-digit day |
| `{hour}` / `{minute}` | Time components |
| `{date}` | `YYYY-MM-DD` |
| `{time}` | `HH-MM-SS` |
| `{created_year}` etc. | Same but from creation date |
| `{size}` | File size in bytes |

## Multiple config files

Want to organise rules by topic? Use `include:` with separate YAML files:

```
~/.config/doumi/
├── config.yaml          ← main config
├── desktop.yaml         ← imported in config.yaml
└── downloads.yaml
```

_(Import support coming in v0.2)_

## License

GPL 3.0
