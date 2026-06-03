<#
.SYNOPSIS
    Build Doumi for Windows.

.DESCRIPTION
    Builds doumi.exe, doumid.exe, and optionally doumi-gui.exe
    from the Rust workspace. Produces release binaries by default.

.PARAMETER Debug
    Build debug binaries instead of release.

.PARAMETER NoGui
    Skip building the GTK4 GUI component (doumi-gui).

.PARAMETER Target
    Rust target triple (default: x86_64-pc-windows-msvc).

.EXAMPLE
    .\build.ps1
    .\build.ps1 -Debug
    .\build.ps1 -NoGui
#>

param(
    [switch]$Debug,
    [switch]$NoGui,
    [string]$Target = "x86_64-pc-windows-msvc"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path "$ScriptDir\.."

Push-Location $ProjectRoot

Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           Doumi Windows Build Script               ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ─── Check prerequisites ────────────────────────────────────────────────────

Write-Host "[1/5] Checking prerequisites..." -ForegroundColor Yellow

try {
    $rustVer = rustc --version
    Write-Host "  Rust: $rustVer" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Rust is not installed. Install from https://rustup.rs" -ForegroundColor Red
    exit 1
}

try {
    $cargoVer = cargo --version
    Write-Host "  Cargo: $cargoVer" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Cargo not found." -ForegroundColor Red
    exit 1
}

# Check target
$installed = rustup target list --installed 2>$null | Select-String $Target
if (-not $installed) {
    Write-Host "  Installing target: $Target" -ForegroundColor Yellow
    rustup target add $Target
}

# ─── Build configuration ────────────────────────────────────────────────────

$profile = if ($Debug) { "debug" } else { "release" }
$targetDir = "target\$Target\$profile"
$flags = @("--target", $Target)
if (-not $Debug) {
    $flags += "--release"
}

Write-Host ""
Write-Host "[2/5] Building doumi-core (shared library)..." -ForegroundColor Yellow
cargo build -p doumi-core @flags
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: doumi-core build failed" -ForegroundColor Red
    exit 1
}
Write-Host "  OK" -ForegroundColor Green

Write-Host ""
Write-Host "[3/5] Building doumid.exe (daemon)..." -ForegroundColor Yellow
cargo build -p doumid @flags
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: doumid build failed" -ForegroundColor Red
    exit 1
}
Write-Host "  OK" -ForegroundColor Green

Write-Host ""
Write-Host "[4/5] Building doumi.exe (CLI)..." -ForegroundColor Yellow
cargo build -p doumi @flags
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: doumi build failed" -ForegroundColor Red
    exit 1
}
Write-Host "  OK" -ForegroundColor Green

if (-not $NoGui) {
    Write-Host ""
    Write-Host "[5/5] Building doumi-gui.exe (GUI)..." -ForegroundColor Yellow
    Write-Host "  NOTE: Requires GTK4 runtime. See https://www.gtk.org/docs/installations/windows/" -ForegroundColor DarkYellow
    cargo build -p doumi-gui @flags 2>&1 | ForEach-Object {
        if ($_ -match "error") {
            Write-Host "  $_" -ForegroundColor Red
        }
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: GUI build failed (GTK4 may not be installed). Skipping." -ForegroundColor Yellow
        Write-Host "  Install GTK4 via MSYS2 or vcpkg to enable the GUI." -ForegroundColor DarkYellow
    } else {
        Write-Host "  OK" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "[5/5] Skipping GUI (--no-gui)" -ForegroundColor Yellow
}

# ─── Summary ─────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Build complete!                                    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$exeExt = ".exe"
Get-ChildItem "$targetDir\doumi$exeExt" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  CLI:    $($_.FullName)  ($([math]::Round($_.Length/1KB,1)) KB)" -ForegroundColor Green
}
Get-ChildItem "$targetDir\doumid$exeExt" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  Daemon: $($_.FullName)  ($([math]::Round($_.Length/1KB,1)) KB)" -ForegroundColor Green
}
Get-ChildItem "$targetDir\doumi-gui$exeExt" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  GUI:    $($_.FullName)  ($([math]::Round($_.Length/1KB,1)) KB)" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Run .\install.ps1 to install to %LOCALAPPDATA%\Programs\Doumi" -ForegroundColor White

Pop-Location
