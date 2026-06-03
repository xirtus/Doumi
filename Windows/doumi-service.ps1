<#
.SYNOPSIS
    Manage Doumi as a Windows scheduled task (auto-start on login).

.DESCRIPTION
    Creates or removes a scheduled task that runs doumid.exe at user login.
    This is the Windows equivalent of systemd --user service or rc.d.

.PARAMETER Action
    install   — Create the scheduled task
    uninstall — Remove the scheduled task
    status    — Show task status

.PARAMETER DryRun
    Run daemon in dry-run mode (preview only, no files touched).

.PARAMETER Debug
    Run daemon with debug logging.

.PARAMETER BinaryPath
    Path to doumid.exe (default: same directory as this script).

.EXAMPLE
    .\doumi-service.ps1 install
    .\doumi-service.ps1 install -DryRun
    .\doumi-service.ps1 uninstall
    .\doumi-service.ps1 status
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("install", "uninstall", "status")]
    [string]$Action,

    [switch]$DryRun,
    [switch]$Debug,

    [string]$BinaryPath = ""
)

$ErrorActionPreference = "Stop"
$TaskName = "Doumi File Organizer"

# Determine binary location
if (-not $BinaryPath) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $BinaryPath = Join-Path $ScriptDir "doumid.exe"
}

function Get-TaskStatus {
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        Write-Host "Task:     $TaskName" -ForegroundColor White
        Write-Host "State:    $($task.State)" -ForegroundColor $(if ($task.State -eq "Ready") { "Green" } else { "Yellow" })
        Write-Host "Path:     $($task.TaskPath)" -ForegroundColor Gray
        if ($task.Actions) {
            foreach ($action in $task.Actions) {
                Write-Host "Command:  $($action.Execute) $($action.Arguments)" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "Task '$TaskName' is not installed." -ForegroundColor Red
    }
}

switch ($Action) {
    "install" {
        Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║    Install Doumi as Scheduled Task (login start)    ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""

        if (-not (Test-Path $BinaryPath)) {
            Write-Host "ERROR: doumid.exe not found at: $BinaryPath" -ForegroundColor Red
            Write-Host "Build first with .\build.ps1 or specify -BinaryPath" -ForegroundColor Yellow
            exit 1
        }

        Write-Host "Binary:   $BinaryPath" -ForegroundColor White

        # Build arguments
        $args = @()
        if ($DryRun) { $args += "--dry-run" }
        if ($Debug)  { $args += "--debug" }

        $argString = if ($args) { $args -join " " } else { "" }

        # Remove existing task if present
        try {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop 2>$null
            Write-Host "Removed existing task." -ForegroundColor Yellow
        } catch {
            # Not found is fine
        }

        # Create the task action
        $action = New-ScheduledTaskAction `
            -Execute $BinaryPath `
            -Argument $argString `
            -WorkingDirectory (Split-Path -Parent $BinaryPath)

        # Trigger: at user logon
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

        # Settings: don't stop when idle, restart on failure
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RestartInterval (New-TimeSpan -Minutes 5) `
            -RestartCount 3 `
            -MultipleInstances IgnoreNew

        # Principal: run with highest privileges NOT needed (user-level)
        $principal = New-ScheduledTaskPrincipal `
            -UserId $env:USERNAME `
            -LogonType Interactive `
            -RunLevel Limited

        # Register
        try {
            Register-ScheduledTask `
                -TaskName $TaskName `
                -Action $action `
                -Trigger $trigger `
                -Settings $settings `
                -Principal $principal `
                -Description "Doumi file automation daemon — watches folders and runs rules" `
                -Force | Out-Null

            Write-Host ""
            Write-Host "  Scheduled task created successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "  Task name: $TaskName" -ForegroundColor White
            Write-Host "  The daemon will start automatically when you log in." -ForegroundColor White
            Write-Host ""
            Write-Host "  To start it now (without logging out):" -ForegroundColor Gray
            Write-Host "    Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray

        } catch {
            Write-Host "ERROR: Failed to create scheduled task: $_" -ForegroundColor Red
            Write-Host ""
            Write-Host "Try running PowerShell as the current user (not Administrator)." -ForegroundColor Yellow
            exit 1
        }
    }

    "uninstall" {
        Write-Host "Removing scheduled task '$TaskName'..." -ForegroundColor Yellow
        try {
            # Stop first if running
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue 2>$null
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Write-Host "  Task removed." -ForegroundColor Green
        } catch {
            Write-Host "  Task not found (already removed)." -ForegroundColor Yellow
        }
    }

    "status" {
        Get-TaskStatus
    }
}
