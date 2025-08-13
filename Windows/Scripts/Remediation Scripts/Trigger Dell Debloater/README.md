# Trigger Dell Debloater (PowerShell)

Remediates Dell Windows endpoints by removing preinstalled OEM applications and services that are not required for enterprise use.  
The script is **Dell-aware** (exits on non-Dell devices), logs to `C:\ProgramData\Debloat\Debloat.log`, and is suitable for Intune Remediations or Win32 app deployment.

---

## What it does

- Creates `C:\ProgramData\Debloat\` and starts a transcript log
- Confirms the device manufacturer contains **Dell**
- Builds a list of **unwanted Dell apps** and removes them via:
  - `Remove-AppxProvisionedPackage -Online`
  - `Remove-AppxPackage -AllUsers`
  - **CIM uninstall** fallback (`Win32_Product` → `Invoke-CimMethod -Uninstall`)
- Preserves items in the **allowlist** (e.g., *Dell Command | Update*)
- Writes start/end timestamps to the log

---

## Files

- `Trigger_DellDebloater.ps1` – main script
- `C:\ProgramData\Debloat\Debloat.log` – run log (auto-created)

---

## Prerequisites

- Windows 10/11 with PowerShell 5.1+
- Local admin context (Intune runs as SYSTEM by default)

> **Note on Win32_Product:** The script uses a CIM uninstall fallback. `Win32_Product` can trigger an MSI consistency check. Prefer Appx/AppxProvisioned removal paths; consider disabling/adjusting the CIM section if you want to avoid potential MSI repairs.

---

## Customization

### Allowlist
Modify the `$WhitelistedApps` array to **keep** specific Dell tools:
```powershell
$WhitelistedApps = @(
  "Dell Command | Update",
  "Dell Command | Update for Windows Universal",
  "Dell Command | Update for Windows 10"
)