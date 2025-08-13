# Define possible install locations of dcu-cli.exe
$possiblePaths = @(
    'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe',
    'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe'
)

# Pick the first existing path
$exePath = $possiblePaths |
    Where-Object { Test-Path -Path $_ } |
    Select-Object -First 1

if (-not $exePath) {
    Write-Error "Could not find dcu-cli.exe in either Program Files folder."
    exit 1
}

# Prepare arguments for silent scan and install
$scanArgs    = '/scan','-silent', '-OutputLog=C:\Windows\Temp\dcu-cli.log'
$applyArgs   = '/applyUpdates','-silent','-reboot=disable','-forceUpdate=enable'

try {
    # Launch the scan  (hidden window)
    Start-Process -FilePath $exePath `
        -ArgumentList $scanArgs `
        -NoNewWindow `
        -ErrorAction Stop `
        -Wait
    
    Write-Host "Dell Command | Update scan completed successfully."

    # Launch the apply-updates (hidden window)
    Start-Process -FilePath $exePath `
        -ArgumentList $applyArgs `
        -NoNewWindow `
        -ErrorAction Stop
}
catch {
    Write-Error "Failed to start Dell Command | Update: $_"
    exit 1
}