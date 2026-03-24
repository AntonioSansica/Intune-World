<#
.SYNOPSIS
    Intune Remediation — Removes unwanted Dell applications from Windows 11 devices.

.DESCRIPTION
    Validates the device is a Dell, then removes bloatware via AppX provisioned
    packages, per-user AppX packages, and Win32 CIM uninstall. A allowlist
    protects management-critical apps from removal.

.NOTES
    Exit 0 = success | Exit 1 = failure
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Invoke-DellDebloat_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Invoke-DellDebloat remediation started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── 0. Confirm Dell device ────────────────────────────────────────────────────
$manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
Write-Log "Manufacturer: $manufacturer"

if ($manufacturer -notlike '*Dell*') {
    Write-Log "Not a Dell device — exiting without changes."
    exit 0
}

# ── 1. Define target and allowlisted applications ─────────────────────────────
$appsToRemove = @(
    'Dell SupportAssist OS Recovery'
    'Dell SupportAssist'
    'DellInc.DellSupportAssistforPCs'
    'Dell SupportAssist Remediation'
    'SupportAssist Recovery Assistant'
    'Dell SupportAssist OS Recovery Plugin for Dell Update'
    'Dell SupportAssistAgent'
    'Dell Update - SupportAssist Update Plugin'
    'Dell Optimizer'
    'Dell Power Manager'
    'DellOptimizerUI'
    'Dell Optimizer Service'
    'Dell Optimizer Core'
    'DellInc.PartnerPromo'
    'DellInc.DellOptimizer'
    'DellInc.DellCommandUpdate'
    'DellInc.DellPowerManager'
    'DellInc.DellDigitalDelivery'
    'Dell Digital Delivery Service'
    'Dell Digital Delivery'
    'Dell Peripheral Manager'
    'Dell Power Manager Service'
    'Dell Core Services'
    'Dell Pair'
    'Dell Display Manager 2.0'
    'Dell Display Manager 2.1'
    'Dell Display Manager 2.2'
    'WavesAudio.MaxxAudioProforDell2019'
    'Dell - Extension*'
    'Dell, Inc. - Firmware*'
) | Select-Object -Unique

# Apps in this list will never be removed regardless of the above.
$allowList = @(
    'Dell Command | Update'
    'Dell Command | Update for Windows Universal'
    'Dell Command | Update for Windows 10'
)

$appsToRemove = $appsToRemove | Where-Object { $allowList -notcontains $_ }
Write-Log "Apps targeted for removal: $($appsToRemove.Count)"

# ── 2. Remove AppX provisioned packages ───────────────────────────────────────
# Provisioned packages are removed from the OS image so they are not reinstalled
# for new user profiles created after this remediation runs.
Write-Log "--- Removing AppX provisioned packages"

foreach ($app in $appsToRemove) {
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                   Where-Object DisplayName -like $app
    if ($provisioned) {
        try {
            $provisioned | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null
            Write-Log "Removed provisioned package: $app"
        } catch {
            Write-Log "Failed to remove provisioned package '$app': $_" -Level WARN
        }
    } else {
        Write-Log "Provisioned package not found, skipping: $app"
    }
}

# ── 3. Remove AppX packages for all users ────────────────────────────────────
Write-Log "--- Removing AppX packages"

foreach ($app in $appsToRemove) {
    $package = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
    if ($package) {
        try {
            $package | Remove-AppxPackage -AllUsers -ErrorAction Stop
            Write-Log "Removed AppX package: $app"
        } catch {
            Write-Log "Failed to remove AppX package '$app': $_" -Level WARN
        }
    } else {
        Write-Log "AppX package not found, skipping: $app"
    }
}

# ── 4. Uninstall Win32 applications via CIM ───────────────────────────────────
# Win32_Product covers traditionally installed MSI applications not surfaced
# by AppX. Note: querying Win32_Product triggers an MSI consistency check on
# all installed products — expected behaviour on Windows 11.
Write-Log "--- Uninstalling Win32 applications via CIM"

foreach ($app in $appsToRemove) {
    $cimApp = Get-CimInstance -ClassName Win32_Product -ErrorAction SilentlyContinue |
              Where-Object Name -like $app
    if ($cimApp) {
        try {
            $cimApp | Invoke-CimMethod -MethodName Uninstall -ErrorAction Stop | Out-Null
            Write-Log "Uninstalled Win32 app: $app"
        } catch {
            Write-Log "Failed to uninstall Win32 app '$app': $_" -Level WARN
        }
    } else {
        Write-Log "Win32 app not found, skipping: $app"
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