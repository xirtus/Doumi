# Doumi Packaging

This directory contains everything needed to create system packages for Doumi.

## Debian / Ubuntu / Mint (.deb)

### Build the package

```bash
./packaging/make-deb.sh
```

This produces `target/doumi_0.1.0_amd64.deb`.

Requirements: `cargo`, `rustc`, `dpkg-deb` (from `dpkg-dev` on Debian/Ubuntu).

### Install

```bash
sudo dpkg -i target/doumi_0.1.0_amd64.deb
# or
sudo apt install ./target/doumi_0.1.0_amd64.deb
```

### Remove

```bash
sudo dpkg -r doumi      # remove (keep config)
sudo dpkg -P doumi      # purge (remove config too)
```

---

## Arch Linux / Manjaro (.pkg.tar.xz)

### Build the package

```bash
cd packaging/arch
makepkg -si     # build and install
# or just build:
makepkg
```

Requirements: `base-devel`, `cargo`, `rust`, `gtk4`, `libadwaita`.

### Install

```bash
sudo pacman -U doumi-0.1.0-1-x86_64.pkg.tar.xz
```

### Remove

```bash
sudo pacman -R doumi       # remove
sudo pacman -Rns doumi     # remove + unused deps
```

---

## Post-install usage (both package types)

```bash
# Start the daemon
doumi daemon start

# Create your first rule
doumi rules add "Sort Downloads" -f ~/Downloads

# List rules
doumi rules list

# Edit rules visually
doumi gui

# Enable auto-start on login
systemctl --user enable --now doumi

# View recent actions
doumi logs -n 20
```

Config lives in `~/.config/doumi/`. Rule JSON files are in `~/.config/doumi/rules/`.

---

## FreeBSD (.pkg)

### Build and install

```bash
cd packaging/freebsd
make install clean
```

Or use the quick install script:

```bash
./install-bsd.sh
```

### Post-install usage

```bash
# Start the daemon
service doumid start

# Enable auto-start on boot
sysrc doumid_enable=YES

# Create your first rule
doumi rules add "Sort Downloads" -f ~/Downloads

# Launch the GUI
doumi gui
```

See `packaging/freebsd/README.md` for details on porting to NetBSD, OpenBSD, and DragonFly BSD.
