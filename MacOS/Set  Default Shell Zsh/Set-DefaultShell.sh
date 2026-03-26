#!/bin/zsh

##############################################################
# Intune Platform Script — Enforce ZSH as default shell
#
# Checks all local user accounts and changes the default shell
# to /bin/zsh for any user currently using a different shell.
#
# Exit 0 = success | Exit 1 = failure
# Log: /opt/Intune/Scripts/Set-DefaultShellZsh.log
##############################################################

# ── Logging ───────────────────────────────────────────────
scriptName="Set-DefaultShellZsh"
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
log "INFO" "Checking Desktop status..."
dockStatus=$(pgrep -x Dock)
until [[ -n $dockStatus ]]; do
    log "INFO" "Desktop not yet loaded, retrying in 30s..."
    sleep 30
    dockStatus=$(pgrep -x Dock)
done
log "INFO" "Desktop loaded. Proceeding."

# ── Enforce ZSH for all local users ──────────────────────
# Exclude system accounts (prefixed with _), root, nobody, and daemon.
# Read users into an array to avoid word-splitting issues with spaces in output.
targetShell="/bin/zsh"
anyFailure=0

users=("${(@f)$(dscl . -list /Users | grep -vE '^_|^root$|^nobody$|^daemon$')}")

if [[ ${#users[@]} -eq 0 ]]; then
    log "WARN" "No eligible user accounts found."
    exit 0
fi

for user in "${users[@]}"; do
    # Trim any whitespace
    user="${user// /}"

    currentShell=$(dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '/UserShell:/ {print $2}')

    if [[ -z "$currentShell" ]]; then
        log "WARN" "Could not read shell for user: $user — skipping."
        continue
    fi

    if [[ "$currentShell" == "$targetShell" ]]; then
        log "INFO" "Shell already set to zsh for user: $user — skipping."
        continue
    fi

    log "INFO" "Changing shell from '$currentShell' to '$targetShell' for user: $user"
    chsh -s "$targetShell" "$user"

    # Verify the change was applied.
    appliedShell=$(dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '/UserShell:/ {print $2}')
    if [[ "$appliedShell" == "$targetShell" ]]; then
        log "INFO" "Shell successfully changed to zsh for user: $user"
    else
        log "ERROR" "Failed to change shell for user: $user (current: $appliedShell)"
        anyFailure=1
    fi
done

# ── Done ──────────────────────────────────────────────────
if [[ $anyFailure -eq 1 ]]; then
    log "ERROR" "=== $scriptName completed WITH ERRORS - review log above ==="
    exit 1
else
    log "INFO" "=== $scriptName completed successfully ==="
    exit 0
fi