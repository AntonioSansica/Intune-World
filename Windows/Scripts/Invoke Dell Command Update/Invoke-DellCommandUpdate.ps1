<#
.SYNOPSIS
    Intune Remediation — Runs Dell Command | Update to scan and apply updates.

.DESCRIPTION
    Locates dcu-cli.exe, runs a silent scan, then applies all available updates
    with reboot suppressed. Designed for Dell devices managed via Intune where
    driver and firmware updates are handled outside Windows Update.

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
    DCU log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\dcu-cli.log
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Invoke-DellCommandUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$DcuLog  = Join-Path $LogDir 'dcu-cli.log'

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

Write-Log "=== Invoke-DellCommandUpdate remediation started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── 1. Locate dcu-cli.exe ─────────────────────────────────────────────────────
$possiblePaths = @(
    'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe',
    'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe'
)

$exePath = $possiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $exePath) {
    Write-Log "dcu-cli.exe not found. Dell Command | Update may not be installed." -Level ERROR
    exit 1
}

Write-Log "Found dcu-cli.exe: $exePath"

# ── 2. Run scan ───────────────────────────────────────────────────────────────
$scanArgs = '/scan', '-silent', "-OutputLog=$DcuLog"

try {
    $scan = Start-Process -FilePath $exePath `
                          -ArgumentList $scanArgs `
                          -Wait -PassThru -NoNewWindow -ErrorAction Stop
    Write-Log "Scan completed (exit: $($scan.ExitCode))"

    # DCU exit code 500 = no updates found, which is a valid success state.
    if ($scan.ExitCode -notin @(0, 500)) {
        Write-Log "Scan returned unexpected exit code: $($scan.ExitCode)" -Level WARN
    }
} catch {
    Write-Log "Scan failed: $_" -Level ERROR
    Set-Failure
}

# ── 3. Apply updates ──────────────────────────────────────────────────────────
# -reboot=disable   — prevents DCU from rebooting the device mid-remediation.
# -forceUpdate=enable — applies updates even if DCU considers them optional.
$applyArgs = '/applyUpdates', '-silent', '-reboot=disable', '-forceUpdate=enable', "-OutputLog=$DcuLog"

try {
    $apply = Start-Process -FilePath $exePath `
                           -ArgumentList $applyArgs `
                           -Wait -PassThru -NoNewWindow -ErrorAction Stop
    Write-Log "Apply updates completed (exit: $($apply.ExitCode))"

    if ($apply.ExitCode -notin @(0, 500)) {
        Write-Log "Apply updates returned unexpected exit code: $($apply.ExitCode)" -Level WARN
        Set-Failure
    }
} catch {
    Write-Log "Apply updates failed: $_" -Level ERROR
    Set-Failure
}

# ── Done ──────────────────────────────────────────────────────────────────────
if ($script:anyFailure) {
    Write-Log "=== Remediation completed WITH ERRORS - review log above ===" -Level WARN
    exit 1
} else {
    Write-Log "=== Remediation completed successfully ==="
    exit 0
}