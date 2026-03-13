<#
.SYNOPSIS
    Intune Remediation Script - Reset Microsoft Edge Cloud Policies

.DESCRIPTION
    Targets cloud-delivered Edge policies (Source = "Cloud" in edge://policy).
    These are NOT registry-based — they are cached locally by the Edge browser
    after being fetched from the Microsoft Edge management service (cloud policy).

    This script clears the local cloud policy cache so Edge fetches a fresh copy,
    and also clears any registry remnants for completeness.

.NOTES
    Version     : 2.0
    Exit Codes  : 0 = Success | 1 = Failure
#>

$ErrorCount = 0

Write-Output "=== Edge Cloud Policy Remediation Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

# ── 1. Kill Edge processes so cache files are not locked ───────────────────────
Write-Output "`n[STEP 1] Stopping Microsoft Edge processes..."
try {
    $EdgeProcesses = Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue
    if ($EdgeProcesses) {
        $EdgeProcesses | Stop-Process -Force -ErrorAction Stop
        Write-Output "  [OK] Edge processes stopped."
        Start-Sleep -Seconds 3
    } else {
        Write-Output "  [SKIP] No Edge processes running."
    }
} catch {
    Write-Output "  [WARN] Could not stop Edge: $($_.Exception.Message)"
}

# ── 2. Clear cloud policy cache (per-user profile) ────────────────────────────
# Edge stores cloud policy in each user's AppData. Since remediation runs as
# SYSTEM, we enumerate all user profiles and clear for each one.
Write-Output "`n[STEP 2] Clearing Edge cloud policy cache for all user profiles..."

$CloudPolicyCachePaths = @(
    "Policy",            # Main cloud policy cache folder
    "EdgeCopilot"        # Copilot-related cloud settings
)

$UserProfilesRoot = "C:\Users"
$UserProfiles = Get-ChildItem -Path $UserProfilesRoot -Directory -ErrorAction SilentlyContinue

foreach ($u in $UserProfiles) {
    $EdgeDataPath = Join-Path $u.FullName "AppData\Local\Microsoft\Edge\User Data"

    if (-not (Test-Path $EdgeDataPath)) { continue }

    # Cloud policy cache lives under each Edge profile subdirectory
    $EdgeProfiles = Get-ChildItem -Path $EdgeDataPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^Default$|^Profile \d+$" }

    foreach ($EdgeProfile in $EdgeProfiles) {
        foreach ($CacheFolder in $CloudPolicyCachePaths) {
            $CachePath = Join-Path $EdgeProfile.FullName $CacheFolder
            if (Test-Path $CachePath) {
                try {
                    Remove-Item -Path $CachePath -Recurse -Force -ErrorAction Stop
                    Write-Output "  [REMOVED] $CachePath"
                } catch {
                    Write-Output "  [ERROR]   $CachePath — $($_.Exception.Message)"
                    $ErrorCount++
                }
            }
        }

        # Also remove the cloud policy token/metadata files directly in the profile root
        $CloudPolicyFiles = @(
            "CloudPolicyDMToken",
            "CloudPolicyClientId",
            "Policy Fetch Timestamps"
        )
        foreach ($File in $CloudPolicyFiles) {
            $FilePath = Join-Path $EdgeProfile.FullName $File
            if (Test-Path $FilePath) {
                try {
                    Remove-Item -Path $FilePath -Force -ErrorAction Stop
                    Write-Output "  [REMOVED] $FilePath"
                } catch {
                    Write-Output "  [ERROR]   $FilePath — $($_.Exception.Message)"
                    $ErrorCount++
                }
            }
        }
    }
}

# ── 3. Clear registry-based policies as well (belt-and-suspenders) ────────────
Write-Output "`n[STEP 3] Clearing registry-based Edge policy keys..."

$RegistryPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge",
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge\Recommended",
    "HKCU:\SOFTWARE\Policies\Microsoft\Edge",
    "HKCU:\SOFTWARE\Policies\Microsoft\Edge\Recommended",
    "HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge"
)

foreach ($Path in $RegistryPaths) {
    if (Test-Path $Path) {
        try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Output "  [REMOVED] $Path"
        } catch {
            Write-Output "  [ERROR]   $Path — $($_.Exception.Message)"
            $ErrorCount++
        }
    } else {
        Write-Output "  [SKIP]    Not found: $Path"
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Output "`n=== Summary ==="
Write-Output "  Errors encountered : $ErrorCount"
Write-Output "  Next step          : Edge will re-fetch cloud policies on next launch"
Write-Output "=== Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

if ($ErrorCount -gt 0) { exit 1 } else { exit 0 }