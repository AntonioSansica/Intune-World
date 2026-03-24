<#
.SYNOPSIS
    Intune Detection — Detects a specific certificate in the user certificate store.

.DESCRIPTION
    Searches the Current User Personal certificate store for a certificate
    matching the configured issuer criteria. Intended as a template — populate
    the issuer match criteria section before deploying.

.NOTES
    Exit 0 = certificate not found (compliant)
    Exit 1 = certificate found (triggers remediation)
    Log: $env:LOCALAPPDATA\Microsoft\IntuneManagementExtension\Logs\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Logging ───────────────────────────────────────────────────────────────────
# Detection runs as the logged-on user (required to access CurrentUser cert
# store), so logs are written to LOCALAPPDATA instead of ProgramData.
$LogDir  = "$env:LOCALAPPDATA\Microsoft\IntuneManagementExtension\Logs"
$LogFile = Join-Path $LogDir "Detect-Certificate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Write-Log "=== Detect-Certificate detection started ==="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file   : $LogFile"

# ── Issuer match criteria ─────────────────────────────────────────────────────
# Populate these values with the issuer field components of the target certificate.
# Leave any unused variables as empty strings — they will be skipped during matching.
# Tip: open the certificate details and copy the Issuer field verbatim.
$issuerCN = "<issuer-common-name>"       # e.g. "Contoso Intermediate CA"
$issuerOU = "<issuer-org-unit>"          # e.g. "IT Security"
$issuerO  = "<issuer-organisation>"      # e.g. "Contoso Ltd"
$issuerDC = @()                          # e.g. @("DC=contoso", "DC=com")

# ── Search certificate store ──────────────────────────────────────────────────
try {
    Write-Log "Searching Cert:\CurrentUser\My for matching certificates..."

    $certs = Get-ChildItem -Path 'Cert:\CurrentUser\My' -ErrorAction Stop |
             Where-Object {
                 $issuer = $_.Issuer
                 ($issuerCN -eq '' -or $issuer -like "*CN=$issuerCN*") -and
                 ($issuerOU -eq '' -or $issuer -like "*OU=$issuerOU*") -and
                 ($issuerO  -eq '' -or $issuer -like "*O=$issuerO*")   -and
                 ($issuerDC.Count -eq 0 -or
                     ($issuerDC | ForEach-Object { $issuer -like "*$_*" }) -notcontains $false)
             }

    if ($certs) {
        foreach ($cert in $certs) {
            Write-Log "DETECTED: '$($cert.Subject)' | Thumbprint: $($cert.Thumbprint) | Expires: $($cert.NotAfter)" -Level WARN
        }
        Write-Log "=== Detection completed — certificate found, remediation required ===" -Level WARN
        exit 1
    } else {
        Write-Log "No matching certificate found in CurrentUser\My."
        Write-Log "=== Detection completed — compliant ==="
        exit 0
    }
} catch {
    Write-Log "Unexpected error during certificate search: $_" -Level ERROR
    Write-Log "=== Detection completed WITH ERRORS — review log above ===" -Level ERROR
    exit 1
}