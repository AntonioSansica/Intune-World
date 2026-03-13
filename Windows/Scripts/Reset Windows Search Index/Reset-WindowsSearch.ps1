<#
.SYNOPSIS
    Intune Remediation — Resets Windows Search index and service.

.DESCRIPTION
    Stops the Windows Search service, removes the corrupted search index database,
    restarts the service, and forces an index rebuild. Resolves blank Start Menu
    search results and broken File Explorer search on Windows 11.

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Reset-WindowsSearch_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Reset-WindowsSearch remediation started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── 1. Stop Windows Search service ───────────────────────────────────────────
try {
    $svc = Get-Service -Name 'WSearch' -ErrorAction Stop
    if ($svc.Status -ne 'Stopped') {
        Stop-Service -Name 'WSearch' -Force -ErrorAction Stop
        Write-Log "Stopped service: WSearch"
    } else {
        Write-Log "Service already stopped: WSearch"
    }
} catch {
    Write-Log "Failed to stop WSearch: $_" -Level ERROR
    Set-Failure
}

# Give the service time to release file handles on the index database.
Start-Sleep -Seconds 5

# ── 2. Remove the search index database ──────────────────────────────────────
# The index lives in ProgramData and is safe to delete — Windows Search will
# rebuild it automatically when the service restarts. Removing it is the only
# reliable fix for a corrupted index; WSRESET and re-enabling indexing alone
# do not purge a corrupt database.
$indexPath = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows"

if (Test-Path $indexPath) {
    try {
        Get-ChildItem -Path $indexPath -Recurse -Force -ErrorAction Stop |
            Remove-Item -Recurse -Force -ErrorAction Stop
        Write-Log "Cleared search index database: $indexPath"
    } catch {
        Write-Log "Failed to clear search index database: $_" -Level ERROR
        Set-Failure
    }
} else {
    Write-Log "Search index path not found, skipping: $indexPath"
}

# ── 3. Reset Windows Search registry settings ────────────────────────────────
# SetupCompletedSuccessfully = 0 forces Windows Search to re-run its setup
# routine on next start, which includes rebuilding the index configuration.
$searchRegPath = 'HKLM:\SOFTWARE\Microsoft\Windows Search'

if (Test-Path $searchRegPath) {
    try {
        Set-ItemProperty -Path $searchRegPath -Name 'SetupCompletedSuccessfully' -Value 0 -Type DWord -ErrorAction Stop
        Write-Log "Reset registry value: SetupCompletedSuccessfully = 0"
    } catch {
        Write-Log "Failed to reset search registry value: $_" -Level ERROR
        Set-Failure
    }
} else {
    Write-Log "Registry path not found, skipping: $searchRegPath"
}

# ── 4. Restart Windows Search service ────────────────────────────────────────
try {
    Start-Service -Name 'WSearch' -ErrorAction Stop
    Write-Log "Started service: WSearch"
} catch {
    Write-Log "Failed to start WSearch: $_" -Level ERROR
    Set-Failure
}

# ── 5. Force index rebuild via SearchCI ──────────────────────────────────────
# SearchCI.exe is the Windows 11 indexing control tool. /reindex triggers a
# full rebuild without requiring a reboot or user interaction.
$searchCI = "$env:windir\System32\SearchCI.exe"

if (Test-Path $searchCI) {
    try {
        $result = Start-Process -FilePath $searchCI `
                                -ArgumentList '/reindex' `
                                -Wait -PassThru -NoNewWindow -ErrorAction Stop
        Write-Log "Triggered index rebuild via SearchCI.exe (exit: $($result.ExitCode))"
    } catch {
        Write-Log "SearchCI.exe failed: $_" -Level WARN
    }
} else {
    Write-Log "SearchCI.exe not found, skipping forced reindex." -Level WARN
}

# ── Done ──────────────────────────────────────────────────────────────────────
if ($script:anyFailure) {
    Write-Log "=== Remediation completed WITH ERRORS - review log above ===" -Level WARN
    exit 1
} else {
    Write-Log "=== Remediation completed successfully ==="
    exit 0
}