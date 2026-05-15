<#
.SYNOPSIS
    Intune Remediation — Installs all available Windows Updates silently.

.DESCRIPTION
    Ensures the PSWindowsUpdate module is present, scans for available updates,
    installs everything with reboot suppressed, and reports reboot status back
    to Intune via exit code.

    PSWindowsUpdate is installed from PSGallery if not already present.
    No user interaction or parameters required — safe to run as SYSTEM.

.NOTES
    Exit 0    = success, no reboot needed
    Exit 1    = failure
    Exit 1641 = success, reboot required (Intune treats this as success)
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference  = 'Stop'
$ProgressPreference     = 'SilentlyContinue'
$ConfirmPreference      = 'None'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Invoke-WindowsUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Invoke-WindowsUpdate remediation started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "PowerShell : $($PSVersionTable.PSVersion)"
Write-Log "OS         : $((Get-CimInstance Win32_OperatingSystem).Caption)"
Write-Log "Log file   : $LogFile"

# ── 1. Enforce TLS 1.2 ────────────────────────────────────────────────────────
# Required for PSGallery connectivity on older Windows builds where TLS 1.2
# is available but not selected by default by the .NET ServicePointManager.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Write-Log "TLS 1.2 enforced."
} catch {
    Write-Log "Could not enforce TLS 1.2: $_" -Level WARN
}

# ── 2. Ensure NuGet package provider ─────────────────────────────────────────
# PSGallery requires NuGet 2.8.5.201 or later. The provider is installed
# machine-wide (AllUsers) so it is available in the SYSTEM context.
Write-Log "--- Checking NuGet package provider"

try {
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not $nuget -or $nuget.Version -lt [Version]'2.8.5.201') {
        Write-Log "Installing NuGet package provider..."
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 `
            -Force -Scope AllUsers -Confirm:$false | Out-Null
        Write-Log "NuGet package provider installed."
    } else {
        Write-Log "NuGet package provider already present (v$($nuget.Version))."
    }
} catch {
    Write-Log "NuGet provider install failed: $_" -Level ERROR
    exit 1
}

# ── 3. Trust PSGallery ────────────────────────────────────────────────────────
try {
    if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Write-Log "PSGallery set as trusted."
    } else {
        Write-Log "PSGallery already trusted."
    }
} catch {
    Write-Log "Could not set PSGallery as trusted: $_" -Level WARN
}

# ── 4. Ensure PSWindowsUpdate module ─────────────────────────────────────────
Write-Log "--- Checking PSWindowsUpdate module"

try {
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Log "Installing PSWindowsUpdate module from PSGallery..."
        Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers `
            -Confirm:$false -AllowClobber -ErrorAction Stop
        Write-Log "PSWindowsUpdate installed."
    } else {
        Write-Log "PSWindowsUpdate already present."
    }
    Import-Module PSWindowsUpdate -Force -ErrorAction Stop
    Write-Log "PSWindowsUpdate imported."
} catch {
    Write-Log "PSWindowsUpdate install/import failed: $_" -Level ERROR
    exit 1
}

# ── 5. Scan for available updates ─────────────────────────────────────────────
Write-Log "--- Scanning for available updates"

try {
    $available = Get-WindowsUpdate -ErrorAction Stop
} catch {
    Write-Log "Update scan failed: $_" -Level ERROR
    exit 1
}

if (-not $available -or $available.Count -eq 0) {
    Write-Log "No updates available. Device is up to date."
    Write-Log "=== Invoke-WindowsUpdate completed successfully (no updates) ==="
    exit 0
}

Write-Log "Found $($available.Count) update(s):"
foreach ($u in $available) {
    Write-Log "  $($u.KB)  $($u.Title)"
}

# ── 6. Install updates ────────────────────────────────────────────────────────
# -AcceptAll    — suppresses per-update confirmation prompts
# -IgnoreReboot — prevents PSWindowsUpdate from rebooting mid-remediation;
#                 reboot is handled by Intune based on the exit code below
Write-Log "--- Installing updates"

try {
    $installOutput = Install-WindowsUpdate -AcceptAll -IgnoreReboot -Confirm:$false -Verbose 4>&1
    foreach ($entry in $installOutput) { Write-Log $entry.ToString() }
} catch {
    Write-Log "Update installation failed: $_" -Level ERROR
    exit 1
}

# ── 7. Check reboot status ────────────────────────────────────────────────────
# Exit 1641 signals to Intune that updates were applied successfully but a
# reboot is pending. Intune will schedule the reboot per the configured
# restart grace period rather than forcing an immediate restart.
Write-Log "--- Checking reboot status"

try {
    $needsReboot = Get-WURebootStatus -Silent -ErrorAction Stop
    if ($needsReboot) {
        Write-Log "Reboot required after update installation." -Level WARN
        Write-Log "=== Invoke-WindowsUpdate completed successfully (reboot pending) ==="
        exit 1641
    }
} catch {
    Write-Log "Reboot status check failed: $_" -Level WARN
}

Write-Log "=== Invoke-WindowsUpdate completed successfully ==="
exit 0