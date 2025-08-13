# Trigger Lenovo System Update

Runs **Lenovo System Update** (`Tvsu.exe`) silently to search for and install all available updates without rebooting.  
Designed for Intune Remediations or Win32 app deployments on Lenovo Windows endpoints.

---

## What it does

1. Locates `Tvsu.exe` in one of:
   - `C:\Program Files\Lenovo\System Update\Tvsu.exe`
   - `C:\Program Files (x86)\Lenovo\System Update\Tvsu.exe`
2. Executes with:
    - **/CM** – command mode (no UI)
    - **-search A** – search all updates
    - **-action INSTALL** – install found updates
    - **-noicon** – no system tray icon
    - **-includerebootpackages 3** – include packages that may require reboot
    - **-NoReboot** – suppress reboot
3. Runs **asynchronously** (no wait) so updates continue in the background.

---

## Files

- `[ALL] Trigger_LenovoSystemUpdate.ps1` – main script  
- Lenovo System Update internal logs (not modified by script):
- `%ProgramData%\Lenovo\SystemUpdate\logs`
- `%LocalAppData%\Lenovo\SystemUpdate\logs`

---

## Prerequisites

- **Lenovo System Update** installed (provides `Tvsu.exe`)
- Windows 10/11, PowerShell 5.1+
- Runs best as SYSTEM (Intune default) or Local Admin

---

## Customization

- **Reboot behavior:**  
- Keep `-NoReboot` to suppress reboot.  
- Remove it to allow automatic reboot after update install.

- **Update scope:**  
Change `-search A` to `-search R` for recommended only.

- **Logging:**  
System Update logs are handled internally by Lenovo’s utility; you can add your own logging in the script if desired.