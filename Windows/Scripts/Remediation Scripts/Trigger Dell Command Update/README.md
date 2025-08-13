# Trigger Dell Command | Update

Runs **Dell Command | Update** (DCU) from `dcu-cli.exe` to silently scan for updates and apply them without rebooting.  
Designed for Intune Remediations or Win32 app deployments on Dell Windows endpoints.

---

## What it does

1. Locates `dcu-cli.exe` in one of:
   - `C:\Program Files\Dell\CommandUpdate\dcu-cli.exe`
   - `C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe`
2. Executes:
   - **Scan:** `/scan -silent -OutputLog=C:\Windows\Temp\dcu-cli.log`
   - **Apply:** `/applyUpdates -silent -reboot=disable -forceUpdate=enable`
3. Runs scan **synchronously** (waits until it completes) and confirms completion with a console message.
4. Launches the apply step **asynchronously** so updates continue installing in the background.
5. Logs scan results to `C:\Windows\Temp\dcu-cli.log`.

> The apply step does **not** reboot the device. Reboot handling can be managed via Intune or by changing the CLI args.

---

## Files

- `[ALL] Trigger_DellCommandUpdate.ps1` – main script  
- `C:\Windows\Temp\dcu-cli.log` – DCU scan log

---

## Prerequisites

- **Dell Command | Update** installed (provides `dcu-cli.exe`)
- Windows 10/11, PowerShell 5.1+
- Runs best as SYSTEM (Intune default) or Local Admin

---

## Customization

- **Log path:** change the scan argument `-OutputLog=C:\Windows\Temp\dcu-cli.log`.  
  Example for a different folder:
  ```powershell
  $scanArgs = '/scan','-silent', '-OutputLog=C:\Temp\dell.log'
