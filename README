# 🌍 Intune-World
 
A curated collection of **Intune Remediation and Platform scripts** for MDM engineers managing **Windows 11** and **macOS** devices.

---
 
## ⚙️ Standards
 
All scripts follow a consistent set of conventions:
 
- **No `#Requires -RunAsAdministrator`** — scripts run as SYSTEM via Intune and this pragma causes an immediate abort in non-interactive sessions
- **Structured logging** — every script writes timestamped `[INFO]` / `[WARN]` / `[ERROR]` entries to `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`, collected automatically by Intune's **Collect Diagnostics** feature
- **Explicit exit codes** — `exit 0` for success, `exit 1` for failure, consumed directly by the Intune remediation engine
- **Non-destructive where possible** — cache folders are renamed rather than deleted, preserving data for forensic review
- **Multi-profile aware** — scripts that operate on user data enumerate all profiles under `C:\Users` via the registry, since they run as SYSTEM with no user context
 
---

---
 
## 🤝 Contributing
 
Contributions are welcome. Please follow the existing script conventions — consistent header format, `Write-Log` function, `Set-Failure` pattern, and explicit exit codes. Open a PR with a clear description of what the script fixes and which platform and scenario it targets.
 
---