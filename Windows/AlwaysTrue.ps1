<#
.SYNOPSIS
    Intune Detection — Always returns non-compliant to force remediation on every run.

.DESCRIPTION
    Use this as the detection script when the paired remediation should run on
    every scheduled cycle regardless of device state.

.NOTES
    Exit 0 = compliant (never returned)
    Exit 1 = non-compliant (always returned)
#>

Write-Output "Always non-compliant — triggering remediation."
exit 1