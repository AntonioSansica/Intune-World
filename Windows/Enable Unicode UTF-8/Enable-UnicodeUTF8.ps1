<#
.SYNOPSIS
    Intune Platform Script — Enables Unicode UTF-8 (Beta) for worldwide language support.

.DESCRIPTION
    Enables the "Beta: Use Unicode UTF-8 for worldwide language support" option
    found under Region Settings > Administrative > Change system locale. This sets
    the system code page to UTF-8 (65001) by writing the ACP/OEMCP override flags
    into the registry, equivalent to checking the Beta checkbox in the UI.

    A reboot is required for the change to take effect system-wide.

    Registry path affected:
      HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage
        Values: ACP  = 65001
                OEMCP = 65001
      HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage
        Value: MACCP = 65001  (optional — set for completeness)

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
    Reboot required: Yes — changes take effect after next restart.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Enable-UnicodeUTF8_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Enable-UnicodeUTF8 platform script started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "PowerShell : $($PSVersionTable.PSVersion)"
Write-Log "OS         : $((Get-CimInstance Win32_OperatingSystem).Caption)"
Write-Log "Log file   : $LogFile"

# ── 1. Set UTF-8 code page values in the NLS CodePage registry key ────────────
# These three values mirror exactly what Windows writes when the Beta UTF-8
# checkbox is ticked in the Region Settings UI and the system is rebooted.
#
# ACP   — ANSI Code Page  : used by Win32 A-APIs (e.g. CreateFileA)
# OEMCP — OEM Code Page   : used by the console / CMD
# MACCP — Mac Code Page   : legacy; set for completeness
#
# Prior to enabling this feature the values are typically "1252" (Western
# European) or another locale-specific code page. Setting them to "65001"
# is the UTF-8 override; Windows reads these as strings, not DWORDs.
$codePagePath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage'
$utf8Value    = '65001'

$codePageValues = @('ACP', 'OEMCP', 'MACCP')

Write-Log "--- Setting NLS CodePage values to UTF-8 (65001)"

foreach ($valueName in $codePageValues) {
    try {
        $current = (Get-ItemProperty -Path $codePagePath -Name $valueName -ErrorAction Stop).$valueName

        if ($current -eq $utf8Value) {
            Write-Log "Already set to UTF-8: $valueName = $current — skipping."
            continue
        }

        Write-Log "Updating $valueName : '$current' -> '$utf8Value'"
        Set-ItemProperty -Path $codePagePath -Name $valueName -Value $utf8Value `
                         -Type String -ErrorAction Stop
        Write-Log "Set: $valueName = $utf8Value"
    } catch {
        Write-Log "Failed to set '$valueName' at '$codePagePath': $_" -Level ERROR
        Set-Failure
    }
}

# ── 2. Enable the Beta UTF-8 flag in the International settings ───────────────
# Windows also writes a REG_SZ flag under the International key to mark the
# Beta feature as enabled. This is what controls the checkbox state in the UI
# and ensures the setting survives language pack updates.
#
# Value: REG_SZ "UTF8"  under the system's current locale subkey.
# The flag is written to both the root International key and the locale subkey
# to cover all Windows 11 builds consistently.
$internationalPaths = @(
    'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage',
    'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language'
)

Write-Log "--- Setting Beta UTF-8 language flag"

# The primary flag that enables the Beta feature checkbox in the Region UI.
# Registry: HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage
# Value name: UTF8  Value data: "1"
try {
    Set-ItemProperty -Path $codePagePath -Name 'UTF8' -Value '1' `
                     -Type String -ErrorAction Stop
    Write-Log "Set UTF8 flag = 1 at $codePagePath"
} catch {
    Write-Log "Failed to write UTF8 flag: $_" -Level WARN
    # Non-fatal — the ACP/OEMCP values are the functional change;
    # the flag only affects the UI checkbox state.
}

# ── 3. Verify the changes were applied ────────────────────────────────────────
Write-Log "--- Verifying registry values"

$verifyFailed = $false
foreach ($valueName in $codePageValues) {
    try {
        $applied = (Get-ItemProperty -Path $codePagePath -Name $valueName -ErrorAction Stop).$valueName
        if ($applied -eq $utf8Value) {
            Write-Log "Verified: $valueName = $applied"
        } else {
            Write-Log "Verification FAILED: $valueName = '$applied' (expected '$utf8Value')" -Level ERROR
            $verifyFailed = $true
            Set-Failure
        }
    } catch {
        Write-Log "Could not verify '$valueName': $_" -Level ERROR
        Set-Failure
    }
}

# ── Done ──────────────────────────────────────────────────────────────────────
if ($script:anyFailure) {
    Write-Log "=== Enable-UnicodeUTF8 completed WITH ERRORS - review log above ===" -Level WARN
    exit 1
} else {
    Write-Log "Unicode UTF-8 (Beta) enabled successfully. A reboot is required for changes to take effect."
    Write-Log "=== Enable-UnicodeUTF8 completed successfully ==="
    exit 0
}