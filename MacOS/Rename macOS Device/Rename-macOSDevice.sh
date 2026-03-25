#!/bin/zsh

##############################################################
# Intune Platform Script — Rename macOS Device
#
# Naming convention: <CC><LOC><TYPE><RANDOM>
#   CC     = 2-letter company code        e.g. "AB"
#   LOC    = 3-letter location/office     e.g. "MIL"
#   TYPE   = 3-letter device type code    e.g. "CML" (Corporate macOS Laptop)
#   RANDOM = 7-character random hex suffix
#
# Example output: ABMILCML4F2A9B1
#
# Total length is capped at 15 characters for Entra ID / NetBIOS compatibility:
#   2 (CC) + 3 (LOC) + 3 (TYPE) + 7 (random) = 15
#
# Exit 0 = success | Exit 1 = failure
# Log: /opt/Intune/Scripts/Rename-Device.log
##############################################################

# ── Configuration ─────────────────────────────────────────
# Update these values before deploying.
companyCode="<CC>"     # 2 letters  — e.g. "AC"
locationCode="<LOC>"   # 3 letters  — e.g. "AMS"
deviceType="CML"       # 3 letters  — CML = Corporate macOS Laptop

# ── Logging ───────────────────────────────────────────────
scriptName="Rename-Device"
logDir="/opt/Intune/Scripts"
logPath="$logDir/$scriptName.log"

mkdir -p "$logDir"
exec > >(tee -a "$logPath") 2>&1

log() {
    printf "$(date '+%Y-%m-%d %H:%M:%S') | [%s] %s\n" "$1" "$2"
}

log "INFO" "=== $scriptName started ==="
log "INFO" "Running as: $(whoami)"

# ── Wait for Desktop to load ──────────────────────────────
# The script may run at login — wait for Dock to be ready
# before making system changes.
log "INFO" "Checking Desktop status..."
dockStatus=$(pgrep -x Dock)
until [[ -n $dockStatus ]]; do
    log "INFO" "Desktop not yet loaded, retrying in 30s..."
    sleep 30
    dockStatus=$(pgrep -x Dock)
done
log "INFO" "Desktop loaded. Proceeding."

# ── Build device name ─────────────────────────────────────
# Generate a 7-character uppercase random hex suffix.
# od reads from /dev/urandom for cryptographic randomness,
# tr filters to hex characters, head caps it at 7.
randomSuffix=$(od -An -tx1 -N4 /dev/urandom | tr -dc '0-9A-F' | head -c 7)

if [[ -z "$randomSuffix" ]]; then
    log "ERROR" "Failed to generate random suffix. Exiting."
    exit 1
fi

newName="${companyCode}${locationCode}${deviceType}${randomSuffix}"
log "INFO" "Target device name: $newName"

# ── Apply device name ─────────────────────────────────────
currentName=$(scutil --get ComputerName)
log "INFO" "Current device name: $currentName"

if [[ "$currentName" == "$newName" ]]; then
    log "INFO" "Device name is already correct. No changes needed."
    exit 0
fi

# Set all three name properties for full macOS naming consistency.
scutil --set ComputerName  "$newName"
scutil --set LocalHostName "$newName"
scutil --set HostName      "$newName"

# Verify the rename was applied correctly.
appliedName=$(scutil --get ComputerName)
if [[ "$appliedName" == "$newName" ]]; then
    log "INFO" "Device successfully renamed to: $newName"
else
    log "ERROR" "Rename verification failed. Expected '$newName', got '$appliedName'."
    exit 1
fi

log "INFO" "=== $scriptName completed successfully ==="
exit 0