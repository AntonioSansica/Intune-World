<#
.SYNOPSIS
    Resets the Windows Update stack on a Windows 11 device with a broken Windows Update.

.DESCRIPTION
    Designed to run as an Intune Remediation script (SYSTEM context, no interactive
    console). Validates the OS is Windows 11 before proceeding, then stops WU-related
    services, removes stale GPO and MDM policy registry keys, renames the
    SoftwareDistribution and Catroot2 cache folders, re-registers core Update DLLs,
    restarts services, and triggers an immediate WU scan via UsoClient.

    Exit codes (consumed by Intune):
        0  – Remediation completed successfully.
        1  – One or more steps failed; see log for details.

.NOTES
    - Targets Windows 11 only.
    - Do NOT add #Requires -RunAsAdministrator — Intune runs as SYSTEM and that
      pragma causes an immediate abort in a non-interactive session.
    - Do NOT restart IntuneManagementExtension or its scheduled tasks from within
      a remediation script — doing so kills the running remediation job.
    - wuauclt.exe and legacy scripting DLLs are intentionally excluded — they are
      not used by the Windows Update stack on Windows 11.
    - Log is written to C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
      so it is collected automatically by Intune's "Collect diagnostics" feature.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDir "Reset-WindowsUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Reset-WindowsUpdate remediation started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── 1. Stop Windows Update-related services ───────────────────────────────────
# On a broken WU device services may be hung — stop unconditionally.
# usosvc (Update Session Orchestrator) is Windows 10/11-specific and must be
# stopped before wuauserv to avoid it immediately restarting the WU service.
$services = 'usosvc', 'wuauserv', 'bits', 'cryptsvc', 'msiserver'

foreach ($svc in $services) {
    try {
        $s = Get-Service -Name $svc -ErrorAction Stop
        if ($s.Status -ne 'Stopped') {
            Stop-Service -Name $svc -Force -ErrorAction Stop
            Write-Log "Stopped service: $svc"
        } else {
            Write-Log "Service already stopped: $svc"
        }
    } catch {
        Write-Log "Could not stop service '$svc': $_" -Level WARN
    }
}

# Give services time to fully release file handles before renaming folders.
Start-Sleep -Seconds 5

# ── 2. Remove stale Windows Update policy registry keys ──────────────────────
# Both the GPO key and the MDM/PolicyManager cache can leave conflicting values
# that prevent Windows Update from running correctly on Intune-managed devices.
$policyPaths = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
    'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update'
)
foreach ($path in $policyPaths) {
    if (Test-Path $path) {
        try {
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            Write-Log "Removed registry key: $path"
        } catch {
            Write-Log "Failed to remove registry key '$path': $_" -Level ERROR
            Set-Failure
        }
    } else {
        Write-Log "Registry key not present, skipping: $path"
    }
}

# ── 3. Rename SoftwareDistribution and Catroot2 cache folders ─────────────────
# Renamed rather than deleted so the old cache is preserved for diagnostics.
# Windows Update will recreate both folders automatically on next run.
$foldersToRename = @(
    "$env:windir\SoftwareDistribution",
    "$env:windir\System32\catroot2"
)
foreach ($folder in $foldersToRename) {
    if (Test-Path $folder) {
        $stamp   = Get-Date -Format 'yyyyMMddHHmmss'
        $leaf    = Split-Path $folder -Leaf
        $parent  = Split-Path $folder -Parent
        $newPath = Join-Path $parent "${leaf}_old_${stamp}"
        try {
            Rename-Item -Path $folder -NewName $newPath -Force -ErrorAction Stop
            Write-Log "Renamed: $folder  ->  $newPath"
        } catch {
            Write-Log "Failed to rename '$folder': $_" -Level ERROR
            Set-Failure
        }
    } else {
        Write-Log "Folder not found, skipping rename: $folder"
    }
}

# ── 4. Re-register core Windows Update DLLs ──────────────────────────────────
# Only the DLLs actively used by the Windows 11 Update stack.
# atl.dll       – ATL base required by several WU components
# urlmon.dll    – URL handling used during update downloads
# msxml3.dll    – XML parsing for update manifests
# wuapi.dll     – Windows Update Agent public API
# wuaueng.dll   – Core WU engine
# wups.dll      – WU proxy stub
# wups2.dll     – WU proxy stub v2 (still present and used on Win11)
$dlls = @(
    'atl.dll',
    'urlmon.dll',
    'msxml3.dll',
    'wuapi.dll',
    'wuaueng.dll',
    'wups.dll',
    'wups2.dll'
)
foreach ($dll in $dlls) {
    $dllPath = Join-Path "$env:windir\System32" $dll
    if (Test-Path $dllPath) {
        $result = Start-Process -FilePath 'regsvr32.exe' `
                                -ArgumentList "/s `"$dllPath`"" `
                                -Wait -PassThru -NoNewWindow
        if ($result.ExitCode -eq 0) {
            Write-Log "Registered DLL: $dll"
        } else {
            Write-Log "regsvr32 returned exit code $($result.ExitCode) for '$dll'" -Level WARN
        }
    } else {
        Write-Log "DLL not found, skipping: $dll" -Level WARN
    }
}

# ── 5. Restart Windows Update services ───────────────────────────────────────
# Start in reverse order: dependencies first, usosvc last.
[array]::Reverse($services)
foreach ($svc in $services) {
    try {
        Start-Service -Name $svc -ErrorAction Stop
        Write-Log "Started service: $svc"
    } catch {
        Write-Log "Failed to start service '$svc': $_" -Level ERROR
        Set-Failure
    }
}

# ── 6. Trigger an immediate Windows Update scan ───────────────────────────────
# UsoClient is the correct tool on Windows 11 — wuauclt is a stub and does nothing.
# StartInteractiveScan is preferred over StartScan as it elevates scan priority.
try {
    $uso = Start-Process -FilePath "$env:windir\System32\UsoClient.exe" `
                         -ArgumentList 'StartInteractiveScan' `
                         -Wait -PassThru -NoNewWindow -ErrorAction Stop
    Write-Log "Triggered WU scan via UsoClient StartInteractiveScan (exit: $($uso.ExitCode))"
} catch {
    Write-Log "UsoClient failed: $_" -Level ERROR
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