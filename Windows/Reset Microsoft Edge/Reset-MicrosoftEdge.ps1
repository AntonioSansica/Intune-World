<#
.SYNOPSIS
    Intune Remediation — Resets Microsoft Edge cloud policy cache.

.DESCRIPTION
    Kills Edge processes, removes the local cloud policy cache for every user
    profile, and clears registry-based Edge policy keys. Edge will re-fetch
    a fresh policy set on next launch.

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Reset-EdgeCloudPolicies_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Reset-EdgeCloudPolicies remediation started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── 1. Kill Edge processes ────────────────────────────────────────────────────
$edgeProcesses = @('msedge', 'msedgewebview2')

foreach ($proc in $edgeProcesses) {
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

# ── 2. Clear cloud policy cache for all user profiles ────────────────────────
# Cloud policy cache lives under each Edge profile subdirectory inside AppData.
# Running as SYSTEM means we must enumerate C:\Users manually.
$cacheFolders = @('Policy', 'EdgeCopilot')
$cacheFiles   = @('CloudPolicyDMToken', 'CloudPolicyClientId', 'Policy Fetch Timestamps')

$userProfiles = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue

foreach ($userProfile in $userProfiles) {
    $edgeDataPath = Join-Path $userProfile.FullName 'AppData\Local\Microsoft\Edge\User Data'

    if (-not (Test-Path $edgeDataPath)) {
        Write-Log "Edge User Data not found, skipping: $($userProfile.FullName)"
        continue
    }

    $edgeProfiles = Get-ChildItem -Path $edgeDataPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^Default$|^Profile \d+$' }

    foreach ($edgeProfile in $edgeProfiles) {
        Write-Log "--- Processing Edge profile: $($edgeProfile.FullName)"

        foreach ($folder in $cacheFolders) {
            $folderPath = Join-Path $edgeProfile.FullName $folder
            if (Test-Path $folderPath) {
                try {
                    Remove-Item -Path $folderPath -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed folder: $folderPath"
                } catch {
                    Write-Log "Failed to remove folder '$folderPath': $_" -Level ERROR
                    Set-Failure
                }
            } else {
                Write-Log "Folder not present, skipping: $folderPath"
            }
        }

        foreach ($file in $cacheFiles) {
            $filePath = Join-Path $edgeProfile.FullName $file
            if (Test-Path $filePath) {
                try {
                    Remove-Item -Path $filePath -Force -ErrorAction Stop
                    Write-Log "Removed file: $filePath"
                } catch {
                    Write-Log "Failed to remove file '$filePath': $_" -Level ERROR
                    Set-Failure
                }
            } else {
                Write-Log "File not present, skipping: $filePath"
            }
        }
    }
}

# ── 3. Clear registry-based Edge policy keys ──────────────────────────────────
$registryPaths = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge\Recommended',
    'HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge',
    'HKCU:\SOFTWARE\Policies\Microsoft\Edge',
    'HKCU:\SOFTWARE\Policies\Microsoft\Edge\Recommended'
)

foreach ($path in $registryPaths) {
    if (Test-Path $path) {
        try {
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            Write-Log "Removed registry key: $path"
        } catch {
            Write-Log "Failed to remove registry key '$path': $_" -Level ERROR
            Set-Failure
        }
    } else {
        Write-Log "Registry key not present, skipping: $path"
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