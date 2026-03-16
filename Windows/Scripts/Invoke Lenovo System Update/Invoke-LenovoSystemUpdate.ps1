<#
.SYNOPSIS
    Intune Remediation — Runs Lenovo System Update to scan and apply updates.

.DESCRIPTION
    Locates Tvsu.exe, then silently installs all available updates with reboot
    suppressed. Designed for Lenovo devices managed via Intune where driver
    and firmware updates are handled outside Windows Update.

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Invoke-LenovoSystemUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Invoke-LenovoSystemUpdate remediation started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── 1. Locate Tvsu.exe ────────────────────────────────────────────────────────
$possiblePaths = @(
    'C:\Program Files\Lenovo\System Update\Tvsu.exe',
    'C:\Program Files (x86)\Lenovo\System Update\Tvsu.exe'
)

$exePath = $possiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $exePath) {
    Write-Log "Tvsu.exe not found. Lenovo System Update may not be installed." -Level ERROR
    exit 1
}

Write-Log "Found Tvsu.exe: $exePath"

# ── 2. Run silent update ──────────────────────────────────────────────────────
# /CM                        — command-line mode (no GUI)
# -search A                  — search for all update types
# -action INSTALL            — install found updates
# -noicon                    — suppress system tray icon
# -includerebootpackages 3   — include packages that require reboot (without rebooting)
# -NoReboot                  — prevent automatic reboot after install
$tvsuArgs = '/CM -search A -action INSTALL -noicon -includerebootpackages 3 -NoReboot'

try {
    $update = Start-Process -FilePath $exePath `
                            -ArgumentList $tvsuArgs `
                            -Wait -PassThru -NoNewWindow -ErrorAction Stop
    Write-Log "Lenovo System Update completed (exit: $($update.ExitCode))"

    if ($update.ExitCode -ne 0) {
        Write-Log "Tvsu.exe returned unexpected exit code: $($update.ExitCode)" -Level WARN
        Set-Failure
    }
} catch {
    Write-Log "Lenovo System Update failed: $_" -Level ERROR
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