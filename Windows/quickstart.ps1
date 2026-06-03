<#
.SYNOPSIS
    One-command setup for Doumi on Windows.
    Downloads Rust if needed, builds, installs, and starts the daemon.
#>

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           Doumi Quick Start for Windows                     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ─── Check Rust ────────────────────────────────────────────────────────────
Write-Host "[1/4] Checking Rust installation..." -ForegroundColor Yellow
try {
    rustc --version | Out-Null
    Write-Host "  Rust is installed." -ForegroundColor Green
} catch {
    Write-Host "  Rust not found. Installing via rustup..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri https://win.rustup.rs -OutFile "$env:TEMP\rustup-init.exe"
    & "$env:TEMP\rustup-init.exe" -y --default-toolchain stable-msvc
    $env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
    Write-Host "  Rust installed." -ForegroundColor Green
}

# ─── Build ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[2/4] Building Doumi..." -ForegroundColor Yellow
Push-Location (Resolve-Path "$ScriptDir\..")
cargo build --release -p doumi -p doumid
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Build failed!" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "  Build complete." -ForegroundColor Green

# ─── Install ───────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3/4] Installing..." -ForegroundColor Yellow
& "$ScriptDir\install.ps1"

# ─── Start daemon ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[4/4] Starting daemon..." -ForegroundColor Yellow
doumi daemon start

# ─── Done ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Doumi is ready!                                           ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  doumi rules add `"Sort Downloads`" -f `"$env:USERPROFILE\Downloads`"" -ForegroundColor Gray
Write-Host "  doumi rules preview --rule-id <id>" -ForegroundColor Gray
Write-Host "  doumi status" -ForegroundColor Gray
Write-Host ""
Write-Host "Auto-start on login:" -ForegroundColor White
Write-Host "  & `"`$env:LOCALAPPDATA\Programs\Doumi\doumi-service.ps1`" install" -ForegroundColor Gray
Write-Host ""

Read-Host "Press Enter to exit"
