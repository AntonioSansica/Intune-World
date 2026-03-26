<#
.SYNOPSIS
    Intune Remediation — Resets and re-applies the OEM Windows product key.

.DESCRIPTION
    Removes the active product key, clears it from the registry, retrieves the
    OEM key from the firmware (OA3x), and re-applies it. Resolves activation
    issues on devices where the key has become mismatched or corrupted.

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Reset-ProductKey_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Reset-ProductKey remediation started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── 1. Retrieve OEM product key from firmware ─────────────────────────────────
# OA3xOriginalProductKey is embedded in the device firmware by the OEM.
# Get-CimInstance is used instead of the deprecated Get-WmiObject.
try {
    $productKey = (Get-CimInstance -Query 'SELECT OA3xOriginalProductKey FROM SoftwareLicensingService' `
                      -ErrorAction Stop).OA3xOriginalProductKey

    if ([string]::IsNullOrEmpty($productKey)) {
        Write-Log "OEM product key not found in firmware. Device may not have an embedded key." -Level ERROR
        Set-Failure
    } else {
        # Mask the key in the log — show only the last 5 characters.
        $maskedKey = "*****-*****-*****-*****-$($productKey.Split('-')[-1])"
        Write-Log "OEM product key retrieved: $maskedKey"
    }
} catch {
    Write-Log "Failed to retrieve OEM product key: $_" -Level ERROR
    Set-Failure
}

# ── 2. Remove active product key ──────────────────────────────────────────────
if (-not $script:anyFailure) {
    try {
        $result = Start-Process -FilePath 'slmgr.vbs' -ArgumentList '/upk' `
                                -Wait -PassThru -NoNewWindow -ErrorAction Stop
        Write-Log "Removed active product key (exit: $($result.ExitCode))"
    } catch {
        Write-Log "Failed to remove active product key: $_" -Level ERROR
        Set-Failure
    }
}

# ── 3. Clear product key from registry ───────────────────────────────────────
if (-not $script:anyFailure) {
    try {
        $result = Start-Process -FilePath 'slmgr.vbs' -ArgumentList '/cpky' `
                                -Wait -PassThru -NoNewWindow -ErrorAction Stop
        Write-Log "Cleared product key from registry (exit: $($result.ExitCode))"
    } catch {
        Write-Log "Failed to clear product key from registry: $_" -Level ERROR
        Set-Failure
    }
}

# ── 4. Re-apply OEM product key ───────────────────────────────────────────────
if (-not $script:anyFailure) {
    try {
        $result = Start-Process -FilePath 'slmgr.vbs' -ArgumentList "/ipk $productKey" `
                                -Wait -PassThru -NoNewWindow -ErrorAction Stop
        Write-Log "Re-applied OEM product key (exit: $($result.ExitCode))"
    } catch {
        Write-Log "Failed to re-apply OEM product key: $_" -Level ERROR
        Set-Failure
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