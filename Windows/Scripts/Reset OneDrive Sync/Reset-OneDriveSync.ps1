<#
.SYNOPSIS
    Intune Remediation — Resets OneDrive sync for all user profiles.

.DESCRIPTION
    Kills OneDrive processes, resets the client via /reset for each user profile,
    and restarts OneDrive. Resolves stuck sync, red X icons, and broken sync
    state without uninstalling or affecting synced file content.

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Reset-OneDriveSync_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')] [string]$Level = 'INFO'
    )
    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $entry | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Output $entry
}

$script:anyFailure = $false
function Set-Failure { $script:anyFailure = $true }

Write-Log "=== Reset-OneDriveSync remediation started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── 1. Kill OneDrive processes ────────────────────────────────────────────────
$oneDriveProcesses = @('OneDrive', 'OneDriveStandaloneUpdater')

foreach ($proc in $oneDriveProcesses) {
    $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
    if ($running) {
        try {
            $running | Stop-Process -Force -ErrorAction Stop
            Write-Log "Terminated process: $proc (PID: $($running.Id -join ', '))"
        } catch {
            Write-Log "Failed to terminate process '$proc': $_" -Level WARN
        }
    } else {
        Write-Log "Process not running, skipping: $proc"
    }
}

Start-Sleep -Seconds 3

# ── 2. Reset OneDrive for all user profiles ───────────────────────────────────
# OneDrive is a per-user application — the executable lives inside each user's
# AppData. Running as SYSTEM means we must enumerate C:\Users and invoke the
# reset for each profile using a scheduled task in the user's session context,
# since OneDrive /reset will silently no-op when launched from SYSTEM context.
$userProfiles = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue

foreach ($userProfile in $userProfiles) {
    $oneDrivePath = Join-Path $userProfile.FullName 'AppData\Local\Microsoft\OneDrive\OneDrive.exe'

    if (-not (Test-Path $oneDrivePath)) {
        Write-Log "OneDrive executable not found, skipping: $($userProfile.FullName)"
        continue
    }

    Write-Log "--- Processing profile: $($userProfile.FullName)"

    # Resolve the SID for this profile to target the correct user session.
    $sid = (New-Object System.Security.Principal.NTAccount($userProfile.Name)).Translate(
               [System.Security.Principal.SecurityIdentifier]).Value

    # ── 2a. Reset OneDrive via scheduled task in the user's session ───────────
    # A scheduled task running as the user bypasses the SYSTEM context limitation
    # and ensures /reset is processed correctly by the per-user OneDrive instance.
    $taskName = "OD-Reset-$($userProfile.Name)"
    $action   = New-ScheduledTaskAction -Execute $oneDrivePath -Argument '/reset'
    $principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Highest

    try {
        # Register task, run it immediately, then clean it up.
        Register-ScheduledTask -TaskName $taskName -Action $action `
                               -Principal $principal -Force -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
        Write-Log "Triggered OneDrive /reset for user: $($userProfile.Name)"

        # Wait briefly for OneDrive to process the reset before cleaning up the task.
        Start-Sleep -Seconds 5
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "Cleaned up scheduled task: $taskName"
    } catch {
        Write-Log "Failed to reset OneDrive for '$($userProfile.Name)': $_" -Level ERROR
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Set-Failure
    }

    # ── 2b. Clear OneDrive local sync state cache ─────────────────────────────
    # These folders hold the local sync database and telemetry cache. Clearing
    # them forces OneDrive to rebuild sync state cleanly after the /reset.
    # User files in the OneDrive folder are NOT touched.
    $syncCacheFolders = @(
        'AppData\Local\Microsoft\OneDrive\logs',
        'AppData\Local\Microsoft\OneDrive\setup\logs',
        'AppData\Local\Temp\OneDrive'
    )

    foreach ($relPath in $syncCacheFolders) {
        $fullPath = Join-Path $userProfile.FullName $relPath
        if (Test-Path $fullPath) {
            try {
                Get-ChildItem -Path $fullPath -Recurse -Force -ErrorAction Stop |
                    Remove-Item -Recurse -Force -ErrorAction Stop
                Write-Log "Cleared cache: $fullPath"
            } catch {
                Write-Log "Failed to clear cache '$fullPath': $_" -Level WARN
            }
        } else {
            Write-Log "Cache folder not present, skipping: $fullPath"
        }
    }

    # ── 2c. Restart OneDrive in the user's session ────────────────────────────
    $restartTaskName = "OD-Start-$($userProfile.Name)"
    $startAction     = New-ScheduledTaskAction -Execute $oneDrivePath
    try {
        Register-ScheduledTask -TaskName $restartTaskName -Action $startAction `
                               -Principal $principal -Force -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $restartTaskName -ErrorAction Stop
        Write-Log "Restarted OneDrive for user: $($userProfile.Name)"
        Start-Sleep -Seconds 3
        Unregister-ScheduledTask -TaskName $restartTaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "Cleaned up scheduled task: $restartTaskName"
    } catch {
        Write-Log "Failed to restart OneDrive for '$($userProfile.Name)': $_" -Level WARN
        Unregister-ScheduledTask -TaskName $restartTaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

# ── Done ──────────────────────────────────────────────────────────────────────
if ($script:anyFailure) {
    Write-Log "=== Remediation completed WITH ERRORS - review log above ===" -Level WARN
    exit 1
} else {
    Write-Log "=== Remediation completed successfully ==="
    exit 0
}