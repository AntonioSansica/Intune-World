<#
.SYNOPSIS
    Intune [Remediation|Platform Script] — <Short one-line description>.

.DESCRIPTION
    <Full description of what the script does, why it exists, and any
    important behavioural notes. Wrap at 80 characters.>

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\

    # Optional — remove if not needed:
    # Exit 1641 = success, reboot required (Invoke-WindowsUpdate pattern)
    # Log: $env:LOCALAPPDATA\Microsoft\IntuneManagementExtension\Logs\
    #      (use LOCALAPPDATA instead of ProgramData when running as logged-on user)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "<ScriptName>_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== <ScriptName> [remediation|platform script] started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "PowerShell : $($PSVersionTable.PSVersion)"
Write-Log "OS         : $((Get-CimInstance Win32_OperatingSystem).Caption)"
Write-Log "Log file   : $LogFile"

# ── 1. <Section title> ────────────────────────────────────────────────────────
# <Explain what this section does and why — include any non-obvious behaviour,
# edge cases, or references to Microsoft docs where relevant.>

try {
    # <code>
} catch {
    Write-Log "<Action> failed: $_" -Level ERROR
    Set-Failure
}

# ── 2. <Section title> ────────────────────────────────────────────────────────

# ── Done ──────────────────────────────────────────────────────────────────────
if ($script:anyFailure) {
    Write-Log "=== <ScriptName> completed WITH ERRORS - review log above ===" -Level WARN
    exit 1
} else {
    Write-Log "=== <ScriptName> completed successfully ==="
    exit 0
}