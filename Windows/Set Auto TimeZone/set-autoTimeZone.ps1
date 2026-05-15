<#
.SYNOPSIS
    Intune Platform Script — Enables Location Services and Auto Timezone.

.DESCRIPTION
    Enables the Windows Location Service (lfsvc) system-wide and enables the
    Auto Time Zone Updater service (tzautoupdate) so Windows can set the
    timezone automatically based on device location.

    tzautoupdate runs as a system service and only requires the HKLM consent
    store and the location service to be active — no per-user registry changes
    are needed for timezone automation.

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\

    Registry paths used:
      HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration
        Value : Status          (DWORD 1 = enabled)
      HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location
        Value : Value           (STRING "Allow")
      HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors
        Value : DisableLocation (DWORD 0 = not disabled)
      HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate
        Value : Start           (DWORD 3 = Demand/Automatic)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Enable-LocationAndAutoTimezone_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Enable-LocationAndAutoTimezone started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "PowerShell : $($PSVersionTable.PSVersion)"
Write-Log "OS         : $((Get-CimInstance Win32_OperatingSystem).Caption)"
Write-Log "Log file   : $LogFile"

# ── Helper — set a registry value, creating the key path if required ──────────
function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [Microsoft.Win32.RegistryValueKind]$Type
    )
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            Write-Log "Created registry key: $Path"
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -ErrorAction Stop
        Write-Log "Set registry value  : $Path\$Name = $Value ($Type)"
    } catch {
        Write-Log "Failed to set '$Path\$Name': $_" -Level ERROR
        Set-Failure
    }
}

# ── 1. Enable the Location Service (lfsvc) ────────────────────────────────────
# lfsvc is the Windows Location Framework service. tzautoupdate depends on it
# to determine the device's current location and resolve the correct timezone.
Write-Log "--- Enabling Location Service (lfsvc)"

Set-RegistryValue `
    -Path  'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration' `
    -Name  'Status' `
    -Value 1 `
    -Type  DWord

# ── 2. Grant system-wide location consent ─────────────────────────────────────
# tzautoupdate is a system service and only checks the HKLM ConsentStore.
# Setting Value = "Allow" here is sufficient for timezone automation.
Write-Log "--- Setting system-wide location consent (CapabilityAccessManager)"

Set-RegistryValue `
    -Path  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' `
    -Name  'Value' `
    -Value 'Allow' `
    -Type  String

# ── 3. Ensure no Group Policy key is blocking location ────────────────────────
# If DisableLocation = 1 is set by a prior policy, it silently overrides the
# consent grant above. Explicitly setting it to 0 ensures policy is not
# blocking the location platform.
Write-Log "--- Clearing any policy block on Location Services"

Set-RegistryValue `
    -Path  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' `
    -Name  'DisableLocation' `
    -Value 0 `
    -Type  DWord

# ── 4. Enable the Auto Time Zone Updater service (tzautoupdate) ───────────────
# Start type 3 (Demand) matches Microsoft's documented default for this service.
# The service is then started immediately so the timezone corrects in the
# current session without requiring a reboot.
Write-Log "--- Enabling Auto Time Zone Updater service (tzautoupdate)"

Set-RegistryValue `
    -Path  'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' `
    -Name  'Start' `
    -Value 3 `
    -Type  DWord

try {
    $svc = Get-Service -Name 'tzautoupdate' -ErrorAction Stop
    if ($svc.Status -ne 'Running') {
        Start-Service -Name 'tzautoupdate' -ErrorAction Stop
        Write-Log "Started service: tzautoupdate"
    } else {
        Write-Log "Service already running: tzautoupdate"
    }
} catch {
    Write-Log "Failed to start tzautoupdate: $_" -Level WARN
    # Not escalated to Set-Failure — registry start type ensures it activates
    # on next reboot even if it cannot be started in the current session.
}

# ── 5. Start the Location Service (lfsvc) ─────────────────────────────────────
# lfsvc must be running for tzautoupdate to resolve location in this session.
Write-Log "--- Starting Location Service (lfsvc)"

try {
    $lfsvc = Get-Service -Name 'lfsvc' -ErrorAction Stop
    if ($lfsvc.Status -ne 'Running') {
        Start-Service -Name 'lfsvc' -ErrorAction Stop
        Write-Log "Started service: lfsvc"
    } else {
        Write-Log "Service already running: lfsvc"
    }
} catch {
    Write-Log "Failed to start lfsvc: $_" -Level WARN
}

# ── Done ──────────────────────────────────────────────────────────────────────
if ($script:anyFailure) {
    Write-Log "=== Enable-LocationAndAutoTimezone completed WITH ERRORS - review log above ===" -Level WARN
    exit 1
} else {
    Write-Log "Location Services enabled and Auto Timezone Updater configured successfully."
    Write-Log "=== Enable-LocationAndAutoTimezone completed successfully ==="
    exit 0
}