# Define possible install locations of Tvsu.exe
$possiblePaths = @(
    'C:\Program Files\Lenovo\System Update\Tvsu.exe',
    'C:\Program Files (x86)\Lenovo\System Update\Tvsu.exe'
)

# Pick the first existing path
$exePath = $possiblePaths |
    Where-Object { Test-Path -Path $_ } |
    Select-Object -First 1

if (-not $exePath) {
    Write-Error "Could not find Tvsu.exe in either Program Files folder."
    exit 1
}

# Prepare arguments for silent update
$tvsuArgs = "/CM -search A -action INSTALL -noicon -includerebootpackages 3 -NoReboot"

try {
    # Launch Tvsu.exe asynchronously (no -Wait)
    Start-Process -FilePath $exePath `
        -ArgumentList $tvsuArgs `
        -NoNewWindow `
        -ErrorAction Stop

    # Exit the script immediately, leaving Tvsu.exe running
    exit
}
catch {
    Write-Error "Failed to start System Update: $_"
    exit 1
}