<#
.SYNOPSIS
    Intune Remediation — Removes the active Windows product key and re-applies the OEM key.

.DESCRIPTION
    Clears the installed product key from the licensing service and the registry,
    then reads the OEM product key embedded in UEFI/BIOS (OA3xOriginalProductKey)
    and re-installs it. On next activation attempt Windows will activate cleanly
    against the hardware-bound OEM licence.

    Run this when a device has an incorrect or stale key installed — for example
    after an OS refresh that applied a volume/generic key over the OEM one.

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
    Requires: SYSTEM context (Intune default). No reboot needed — activation
    resolves on next licence check cycle or can be forced via slmgr /ato.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Reset-WindowsLicense_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Reset-WindowsLicense remediation started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── 1. Read OEM product key from firmware ─────────────────────────────────────
# OA3xOriginalProductKey is injected into UEFI/BIOS by the OEM at manufacture.
# It is the canonical licence for this hardware and survives OS reinstalls.
# Get-CimInstance is used in place of the deprecated Get-WmiObject.
Write-Log "Reading OEM product key from firmware (SoftwareLicensingService)..."

try {
    $sls = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop
    $oemKey = $sls.OA3xOriginalProductKey
} catch {
    Write-Log "Failed to query SoftwareLicensingService: $_" -Level ERROR
    Set-Failure
}

if ([string]::IsNullOrWhiteSpace($oemKey)) {
    Write-Log "No OEM product key found in firmware (OA3xOriginalProductKey is empty)." -Level ERROR
    Write-Log "This device may not have an OEM UEFI-embedded key. Exiting without changes."
    exit 1
}

# Log a masked version of the key for audit purposes — never log keys in plain text.
$maskedKey = $oemKey -replace '^(.{5})-(.{5})-(.{5})-(.{5})-(.{5})$', '$1-XXXXX-XXXXX-XXXXX-$5'
Write-Log "OEM key retrieved successfully. Masked: $maskedKey"

# ── 2. Uninstall the current product key (slmgr /upk) ────────────────────────
# /upk removes the currently installed product key from the licensing service.
# This does not affect the OEM key stored in firmware.
Write-Log "Uninstalling current product key (/upk)..."

try {
    $upk = Start-Process -FilePath "$env:windir\System32\cscript.exe" `
                         -ArgumentList '//NoLogo', "$env:windir\System32\slmgr.vbs", '/upk' `
                         -Wait -PassThru -NoNewWindow -ErrorAction Stop
    Write-Log "/upk completed (exit: $($upk.ExitCode))"

    if ($upk.ExitCode -ne 0) {
        Write-Log "/upk returned non-zero exit code: $($upk.ExitCode)" -Level WARN
    }
} catch {
    Write-Log "Failed to run slmgr /upk: $_" -Level ERROR
    Set-Failure
}

# ── 3. Clear the product key from the registry (slmgr /cpky) ─────────────────
# /cpky removes the product key from the registry to prevent recovery tools
# from reading the previously installed key. Safe to run after /upk.
Write-Log "Clearing product key from registry (/cpky)..."

try {
    $cpky = Start-Process -FilePath "$env:windir\System32\cscript.exe" `
                          -ArgumentList '//NoLogo', "$env:windir\System32\slmgr.vbs", '/cpky' `
                          -Wait -PassThru -NoNewWindow -ErrorAction Stop
    Write-Log "/cpky completed (exit: $($cpky.ExitCode))"

    if ($cpky.ExitCode -ne 0) {
        Write-Log "/cpky returned non-zero exit code: $($cpky.ExitCode)" -Level WARN
    }
} catch {
    Write-Log "Failed to run slmgr /cpky: $_" -Level ERROR
    Set-Failure
}

# ── 4. Install the OEM product key (slmgr /ipk) ──────────────────────────────
# /ipk installs the OEM key retrieved from firmware, replacing any previously
# installed key and staging the device for clean OEM activation.
Write-Log "Installing OEM product key (/ipk)..."

try {
    $ipk = Start-Process -FilePath "$env:windir\System32\cscript.exe" `
                         -ArgumentList '//NoLogo', "$env:windir\System32\slmgr.vbs", '/ipk', $oemKey `
                         -Wait -PassThru -NoNewWindow -ErrorAction Stop
    Write-Log "/ipk completed (exit: $($ipk.ExitCode))"

    if ($ipk.ExitCode -ne 0) {
        Write-Log "/ipk returned unexpected exit code: $($ipk.ExitCode)" -Level ERROR
        Set-Failure
    }
} catch {
    Write-Log "Failed to run slmgr /ipk: $_" -Level ERROR
    Set-Failure
}

# ── Done ──────────────────────────────────────────────────────────────────────
if ($script:anyFailure) {
    Write-Log "=== Remediation completed WITH ERRORS - review log above ===" -Level WARN
    exit 1
} else {
    Write-Log "OEM key successfully installed. Windows will activate on next licence check."
    Write-Log "=== Remediation completed successfully ==="
    exit 0
}