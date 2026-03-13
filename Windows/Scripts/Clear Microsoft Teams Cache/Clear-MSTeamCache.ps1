<#
.SYNOPSIS
    Intune Remediation — Clears new Teams (ms-teams) cache for all user profiles.

.DESCRIPTION
    Kills ms-teams.exe, then removes cache folders for every profile found under
    C:\Users. Profile paths are resolved from the registry since the script runs
    as SYSTEM with no user context.

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Clear-TeamsCache_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Clear-TeamsCache remediation started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── 1. Kill all running Teams processes ───────────────────────────────────────
# Only new Teams (ms-teams.exe) is targeted — classic Teams is out of scope.
$teamsProcesses = @('ms-teams')

foreach ($proc in $teamsProcesses) {
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

# Brief pause to ensure file handles are fully released after process termination.
Start-Sleep -Seconds 3

# ── 2. Enumerate all user profiles ───────────────────────────────────────────
# SYSTEM has no %APPDATA%, so profile paths are read directly from the registry.
# Profiles with paths outside C:\Users are skipped (system/service accounts).
$profileListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$profileKeys     = Get-ChildItem -Path $profileListPath -ErrorAction SilentlyContinue

if (-not $profileKeys) {
    Write-Log "No user profiles found in registry. Exiting." -Level ERROR
    exit 1
}

$userProfiles = foreach ($key in $profileKeys) {
    $profilePath = (Get-ItemProperty -Path $key.PSPath -Name 'ProfileImagePath' -ErrorAction SilentlyContinue).ProfileImagePath
    if ($profilePath -like 'C:\Users\*') {
        $profilePath
    }
}

Write-Log "User profiles found: $($userProfiles.Count)"
foreach ($p in $userProfiles) { Write-Log "  $p" }

# ── 3. Define Teams cache folder paths ───────────────────────────────────────
# Paths are relative to each user's profile root.
#
# New Teams (2.0) cache locations:
#   AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams
#   AppData\Local\Microsoft\Teams  (residual / shared token cache)

$allCacheFolders = @(
    'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams',
    'AppData\Local\Microsoft\Teams'
)

# ── 4. Clear cache folders for every user profile ────────────────────────────
foreach ($userProfile in $userProfiles) {
    Write-Log "--- Processing profile: $userProfile"

    foreach ($relPath in $allCacheFolders) {
        $fullPath = Join-Path $userProfile $relPath

        if (Test-Path $fullPath) {
            try {
                # Remove all contents but keep the folder itself so Teams
                # does not error on startup looking for a missing directory.
                Get-ChildItem -Path $fullPath -Recurse -Force -ErrorAction Stop |
                    Remove-Item -Recurse -Force -ErrorAction Stop
                Write-Log "Cleared: $fullPath"
            } catch {
                Write-Log "Failed to clear '$fullPath': $_" -Level ERROR
                Set-Failure
            }
        } else {
            Write-Log "Folder not present, skipping: $fullPath"
        }
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