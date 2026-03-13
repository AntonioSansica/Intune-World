# PowerShell script to debloat Dell devices by removing unwanted applications and services.
$ErrorActionPreference = 'silentlycontinue'

# Create folder + log
$DebloatFolder = "C:\ProgramData\Debloat"
if (-not (Test-Path $DebloatFolder)) {
    New-Item -Path $DebloatFolder -ItemType Directory | Out-Null
}
Start-Transcript -Path "C:\ProgramData\Debloat\Debloat.log" -Append

# Start time (dd-MM-yyyy HH:mm)
Write-Output ("===== Debloat Start: {0} =====" -f (Get-Date -Format "dd-MM-yyyy HH:mm"))

# Only run on Dell devices
if ((Get-CimInstance Win32_ComputerSystem).Manufacturer -notlike "*Dell*") {
    Write-Output "Not a Dell device. Exiting."
    Write-Output ("===== Debloat End: {0} =====" -f (Get-Date -Format "dd-MM-yyyy HH:mm"))
    Stop-Transcript
    exit 0
}

Write-Host "Dell detected"

# Define unwanted Dell apps
$UninstallPrograms = @(
    "Dell SupportAssist OS Recovery"
    "Dell SupportAssist"
    "DellInc.DellSupportAssistforPCs"
    "Dell SupportAssist Remediation"
    "SupportAssist Recovery Assistant"
    "Dell SupportAssist OS Recovery Plugin for Dell Update"
    "Dell SupportAssistAgent"
    "Dell Update - SupportAssist Update Plugin"
    "Dell Optimizer"
    "Dell Power Manager"
    "DellOptimizerUI"
    "Dell Optimizer Service"
    "Dell Optimizer Core"
    "DellInc.PartnerPromo"
    "DellInc.DellOptimizer"
    "DellInc.DellCommandUpdate"
    "DellInc.DellPowerManager"
    "DellInc.DellDigitalDelivery"
    "Dell Digital Delivery Service"
    "Dell Digital Delivery"
    "Dell Peripheral Manager"
    "Dell Power Manager Service"
    "Dell Core Services"
    "Dell Pair"
    "Dell Display Manager 2.0"
    "Dell Display Manager 2.1"
    "Dell Display Manager 2.2"
    "WavesAudio.MaxxAudioProforDell2019"
    "Dell - Extension*"
    "Dell, Inc. - Firmware*"
    "Dell Optimizer Core"
    "Dell SupportAssist Remediation"
    "Dell SupportAssist OS Recovery Plugin for Dell Update"
    "Dell Pair"
    "Dell Display Manager 2.0"
    "Dell Display Manager 2.1"
    "Dell Display Manager 2.2"
    "Dell Peripheral Manager"
) | Select-Object -Unique

# Define allowlist for Dell apps
$WhitelistedApps = @(
    "Dell Command | Update"
    "Dell Command | Update for Windows Universal"
    "Dell Command | Update for Windows 10"
)

# Apply Allowlist
$UninstallPrograms = $UninstallPrograms | Where-Object { $WhitelistedApps -notcontains $_ }

# Uninstall unwanted apps
foreach ($app in $UninstallPrograms) {
    if (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app -ErrorAction SilentlyContinue) {
        
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app | Remove-AppxProvisionedPackage -Online
        Write-Host "Removed provisioned package for $app."
    
    } else {
    
        Write-Host "Provisioned package for $app not found."

    }

    if (Get-AppxPackage -Name $app -ErrorAction SilentlyContinue) {
    
        Get-AppxPackage -allusers -Name $app | Remove-AppxPackage -AllUsers
        Write-Host "Removed $app."

    } else {
        
        Write-Host "$app not found."

    }
}

# Remove via CIM too
foreach ($program in $UninstallPrograms) {

    write-host "Removing $program"
    Get-CimInstance -Classname Win32_Product | Where-Object Name -Match $program | Invoke-CimMethod -MethodName UnInstall

}

Write-Host "Completed"

Write-Output ("===== Debloat End: {0} =====" -f (Get-Date -Format "dd-MM-yyyy HH:mm"))
Stop-Transcript