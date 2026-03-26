<#
.SYNOPSIS
    Intune Platform Script — Enables automatic time zone detection on Windows 11.

.DESCRIPTION
    Enables location services, the Windows Location Platform sensor, and the
    automatic time zone service (tzautoupdate). Ensures the device always
    reflects the correct local time zone without manual configuration.

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Enable-AutoTimezone_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Enable-AutoTimezone started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── Helper — idempotent registry write ───────────────────────────────────────
function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [Microsoft.Win32.RegistryValueKind]$Type = [Microsoft.Win32.RegistryValueKind]::DWord
    )
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
            Write-Log "Created registry key: $Path"
        }
        $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
        if ($current -eq $Value) {
            Write-Log "Already set — skipping: $Path\$Name = $Value"
        } else {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -ErrorAction Stop
            Write-Log "Set: $Path\$Name = $Value"
        }
    } catch {
        Write-Log "Failed to set '$Path\$Name': $_" -Level ERROR
        Set-Failure
    }
}

# ── 1. Enable location access for apps ───────────────────────────────────────
Set-RegistryValue `
    -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' `
    -Name  'Value' `
    -Value 'Allow' `
    -Type  String

# ── 2. Enable automatic time zone service (tzautoupdate) ──────────────────────
# Start value 3 = Manual (enabled, triggered by location service).
Set-RegistryValue `
    -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' `
    -Name  'Start' `
    -Value 3

# ── 3. Enable location services (lfsvc) ──────────────────────────────────────
Set-RegistryValue `
    -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration' `
    -Name  'Status' `
    -Value 1

# ── 4. Enable Windows Location Platform sensor ───────────────────────────────
Set-RegistryValue `
    -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}' `
    -Name  'SensorPermissionState' `
    -Value 1

# ── 5. Restart geolocation service ───────────────────────────────────────────
try {
    $svc = Get-Service -Name 'lfsvc' -ErrorAction Stop
    if ($svc.Status -eq 'Running') {
        Restart-Service -Name 'lfsvc' -Force -ErrorAction Stop
        Write-Log "Restarted service: lfsvc"
    } else {
        Start-Service -Name 'lfsvc' -ErrorAction Stop
        Write-Log "Started service: lfsvc"
    }
} catch {
    Write-Log "Failed to start/restart lfsvc: $_" -Level ERROR
    Set-Failure
}

# ── Done ──────────────────────────────────────────────────────────────────────
if ($script:anyFailure) {
    Write-Log "=== Script completed WITH ERRORS - review log above ===" -Level WARN
    exit 1
} else {
    Write-Log "=== Script completed successfully ==="
    exit 0
}