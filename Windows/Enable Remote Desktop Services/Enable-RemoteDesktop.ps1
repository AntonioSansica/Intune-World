<#
.SYNOPSIS
    Intune Platform Script — Enables Windows Remote Desktop (RDP).

.DESCRIPTION
    Enables RDP via registry, opens the Windows Firewall rule for Remote Desktop,
    disables Network Level Authentication (NLA), and ensures the TermService
    is set to start automatically and is running.

.NOTES
     Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Enable-RDP_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Enable-RDP platform script started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── 1. Enable Remote Desktop in the Registry ──────────────────────────────────
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Name 'fDenyTSConnections' -Value 0 -ErrorAction Stop
    Write-Log "Registry: fDenyTSConnections set to 0 (RDP enabled)"
} catch {
    Write-Log "Failed to set fDenyTSConnections: $_" -Level ERROR
    Set-Failure
}

# ── 2. Open Windows Firewall Rule ─────────────────────────────────────────────
try {
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop
    Write-Log "Firewall: Remote Desktop rule group enabled"
} catch {
    Write-Log "Failed to enable firewall rule: $_" -Level ERROR
    Set-Failure
}

# ── 3. Configure Network Level Authentication (NLA) ───────────────────────────
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
        -Name 'UserAuthentication' -Value 0 -ErrorAction Stop
    Write-Log "Registry: UserAuthentication set to 0 (NLA disabled)"
} catch {
    Write-Log "Failed to set UserAuthentication: $_" -Level ERROR
    Set-Failure
}

# ── 4. Enable and Start TermService ───────────────────────────────────────────
try {
    Set-Service -Name 'TermService' -StartupType Automatic -ErrorAction Stop
    Write-Log "TermService: StartupType set to Automatic"
} catch {
    Write-Log "Failed to set TermService StartupType: $_" -Level ERROR
    Set-Failure
}

try {
    Start-Service -Name 'TermService' -ErrorAction Stop
    Write-Log "TermService: Service started successfully"
} catch {
    Write-Log "Failed to start TermService: $_" -Level ERROR
    Set-Failure
}

# ── Done ──────────────────────────────────────────────────────────────────────
if ($script:anyFailure) {
    Write-Log "=== Script completed WITH ERRORS — review log above ===" -Level WARN
    exit 1
} else {
    Write-Log "=== Script completed successfully ==="
    exit 0
}