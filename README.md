# 🌍 Intune-World
 
A curated collection of **Intune Remediation and Platform scripts** for MDM engineers managing **Windows 11** and **macOS** devices.

---
## ⚙️ Standards
 
All scripts follow a consistent set of conventions regardless of platform:
 
- **Structured logging** — every script writes timestamped entries to a centralised log file, collected automatically by Intune's **Collect Diagnostics** feature
- **Explicit exit codes** — `exit 0` for success, `exit 1` for failure, consumed directly by the Intune engine
- **Non-destructive where possible** — data is renamed or preserved rather than deleted outright, keeping it available for forensic review
 
**Windows specifics:**
- No `#Requires -RunAsAdministrator` — scripts run as SYSTEM via Intune and this pragma causes an immediate abort in non-interactive sessions
- Log path: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`
- Multi-profile aware — scripts that operate on user data enumerate all profiles under `C:\Users` via the registry, since they run as SYSTEM with no user context
 
**macOS specifics:**
- Written in `zsh` — the default shell on macOS since Catalina
- Log path: `/opt/Intune/Scripts/`
- Scripts wait for the Desktop (Dock) to load before executing when user context is required

---
 
## 🤝 Contributing
 
Contributions are welcome. Please follow the existing script conventions — consistent header format, `Write-Log` function, `Set-Failure` pattern, and explicit exit codes. Open a PR with a clear description of what the script fixes and which platform and scenario it targets.
 
---