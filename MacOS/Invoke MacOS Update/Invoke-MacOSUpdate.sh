#!/bin/zsh

##############################################################
# Intune Platform Script — Trigger latest macOS update.
#
# Fetches the latest available macOS update and installs it
# silently without forcing a reboot. The user will be notified
# by macOS that a restart is required.
#
# IMPORTANT: Deploy with "Run script as signed-in user" = No
#            (requires root to install system updates)
#
# Exit 0 = success | Exit 1 = failure
# Log: /opt/Intune/Scripts/Invoke-MacOSUpdate.log
##############################################################

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# ── Logging ───────────────────────────────────────────────
scriptName="Invoke-MacOSUpdate"
logDir="/opt/Intune/Scripts"
logPath="$logDir/$scriptName.log"

mkdir -p "$logDir"
exec > >(tee -a "$logPath") 2>&1

log() {
    printf "$(date '+%Y-%m-%d %H:%M:%S') | [%s] %s\n" "$1" "$2"
}

log "INFO" "=== $scriptName started ==="
log "INFO" "Running as: $(whoami)"

# ── Confirm running as root ───────────────────────────────
if [[ "$(whoami)" != "root" ]]; then
    log "ERROR" "Script must run as root. Set 'Run script as signed-in user' to No in Intune."
    exit 1
fi

# ── Fetch available updates ───────────────────────────────
log "INFO" "Checking for available macOS updates..."
# Capture output and check exit status for better reliability
availableUpdates=$(softwareupdate --list 2>&1)
listExit=$?

if [[ $listExit -ne 0 ]]; then
    log "ERROR" "Failed to list available updates. softwareupdate returned exit code $listExit."
    log "DEBUG" "Output: $availableUpdates"
    exit 1
fi

# Check if there are any recommended updates.
if echo "$availableUpdates" | grep -q "No new software available"; then
    log "INFO" "No updates available. Device is up to date."
    exit 0
fi

# ── Install all recommended updates — no reboot ───────────
# --install --all        installs all recommended updates
# --no-restart           prevents automatic reboot after install
# --agree-to-license     suppresses the license prompt in non-interactive context
log "INFO" "Installing available updates (reboot suppressed)..."
# Capture output and check exit status
installResult=$(softwareupdate --install --all --no-restart --agree-to-license 2>&1)
installExit=$?

log "INFO" "$installResult"

if [[ $installExit -eq 0 ]]; then
    log "INFO" "Updates installed successfully. A restart may be required."
    exit 0
else
    log "ERROR" "softwareupdate exited with code $installExit during installation."
    exit 1
fi

# ── Done ──────────────────────────────────────────────────
log "INFO" "=== $scriptName completed successfully ==="
exit 0