<#
.SYNOPSIS
    Install Doumi for Windows.

.DESCRIPTION
    Copies doumi.exe and doumid.exe to %LOCALAPPDATA%\Programs\Doumi\
    and optionally adds the directory to the user PATH.

.PARAMETER NoPath
    Skip adding to PATH.

.PARAMETER InstallDir
    Custom installation directory (default: %LOCALAPPDATA%\Programs\Doumi).

.EXAMPLE
    .\install.ps1
    .\install.ps1 -InstallDir "C:\Tools\Doumi"
    .\install.ps1 -NoPath
#>

param(
    [switch]$NoPath,
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\Doumi"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ─── Locate binaries ────────────────────────────────────────────────────────
# Priority: 1) same directory (release zip layout)
#           2) ../target/<triple>/release (dev layout)
#           3) ../target/release (dev layout, no triple)

$searchPaths = @(
    $ScriptDir,
    "$ScriptDir\..\target\x86_64-pc-windows-msvc\release",
    "$ScriptDir\..\target\release",
    "$ScriptDir\..\target\x86_64-pc-windows-msvc\debug",
    "$ScriptDir\..\target\debug"
)

$SourceDir = $null
foreach ($p in $searchPaths) {
    if (Test-Path (Join-Path $p "doumi.exe")) {
        $SourceDir = (Resolve-Path $p).Path
        break
    }
}

if (-not $SourceDir) {
    Write-Host "ERROR: doumi.exe not found. Searched:" -ForegroundColor Red
    foreach ($p in $searchPaths) { Write-Host "  $p" -ForegroundColor Gray }
    Write-Host ""
    Write-Host "If building from source, run .\build.ps1 first." -ForegroundColor Yellow
    Write-Host "If using a release zip, place install.ps1 next to doumi.exe." -ForegroundColor Yellow
    exit 1
}

Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           Doumi Windows Installer                   ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Source:   $SourceDir" -ForegroundColor White
Write-Host "Target:   $InstallDir" -ForegroundColor White
Write-Host ""

# ─── Create install dir ─────────────────────────────────────────────────────

if (-not (Test-Path $InstallDir)) {
    Write-Host "Creating $InstallDir ..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# ─── Copy binaries ──────────────────────────────────────────────────────────

Write-Host "Installing binaries..." -ForegroundColor Yellow

$binaries = @(
    @{Name="doumi.exe";   Desc="CLI"},
    @{Name="doumid.exe";  Desc="Daemon"}
)

# Optionally copy GUI if built
if (Test-Path "$SourceDir\doumi-gui.exe") {
    $binaries += @{Name="doumi-gui.exe"; Desc="GUI"}
}

foreach ($bin in $binaries) {
    $src = "$SourceDir\$($bin.Name)"
    $dst = "$InstallDir\$($bin.Name)"
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "  $($bin.Desc): $($bin.Name)  ($([math]::Round((Get-Item $dst).Length/1KB,1)) KB)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: $($bin.Name) not found" -ForegroundColor Yellow
    }
}

# ─── Copy resources ─────────────────────────────────────────────────────────

Write-Host "Copying resources..." -ForegroundColor Yellow

# Copy the service script
$serviceScript = "$ScriptDir\doumi-service.ps1"
if (Test-Path $serviceScript) {
    Copy-Item -Path $serviceScript -Destination "$InstallDir\doumi-service.ps1" -Force
    Write-Host "  Service script: doumi-service.ps1" -ForegroundColor Green
}

# ─── Add to PATH ────────────────────────────────────────────────────────────

if (-not $NoPath) {
    Write-Host ""
    Write-Host "Adding to user PATH..." -ForegroundColor Yellow

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User") ?? ""
    if ($currentPath -split ";" -notcontains $InstallDir) {
        $newPath = if ($currentPath) { "$currentPath;$InstallDir" } else { $InstallDir }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")

        # Also update current process PATH
        $env:Path = "$env:Path;$InstallDir"

        Write-Host "  Added $InstallDir to user PATH" -ForegroundColor Green
        Write-Host "  NOTE: Restart your terminal for PATH changes to take effect." -ForegroundColor DarkYellow
    } else {
        Write-Host "  Already in PATH" -ForegroundColor Green
    }
}

# ─── Success ────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Installation complete!                             ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Quick start:" -ForegroundColor White
Write-Host "  doumi daemon start" -ForegroundColor Gray
Write-Host "  doumi rules add `"Sort Downloads`" -f `"%USERPROFILE%\Downloads`"" -ForegroundColor Gray
Write-Host "  doumi rules preview --rule-id <id>" -ForegroundColor Gray
Write-Host ""
Write-Host "Run as a service (auto-start on login):" -ForegroundColor White
Write-Host "  & `"$InstallDir\doumi-service.ps1`" install" -ForegroundColor Gray
