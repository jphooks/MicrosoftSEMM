###############################################################################
# This script must be run on a Surface you wish to add the UEFI password to   #
###############################################################################

# Start Logging
cls
$LogDate = (get-date).ToString("yyyy-MM-dd_HH_mm_ss")
Start-Transcript "c:\windows\temp\SurfaceUEFI_PS_$LogDate.log"

# Set the script directory whether it's ran from ISE or not
if ($PSScriptRoot){$scriptdir = $PSScriptRoot}
else{$scriptdir = Split-Path -Path $psISE.CurrentFile.FullPath}

# Find the MSI in the script root directory
Write-Host "`n====================================================================================" -ForegroundColor Gray
Write-Host "Searching for MSI in script root directory" -ForegroundColor Cyan
$MSIFile = @(GCI $scriptdir *.msi)

# Exit if there's more or less than 1 MSI
if ($MSIFile.count -ne 1){
    Write-Host "Found MSI: " ($MSIFile.Name -join ', ') -ForegroundColor Red
    Write-Host "Ensure there is only 1 MSI file in the script root directory for the SurfaceUEFI_Configurator." -ForegroundColor Red
    Exit
    }
else{
    Write-Host "Found MSI: " $MSIFile[0].Name -ForegroundColor Green
    }

# Check to see if MSI is already installed
Write-Host "`n====================================================================================" -ForegroundColor Gray
$InstalledApp = Get-childitem -Path Registry::HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall, Registry::HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction SilentlyContinue | Get-ItemProperty | Where-Object {$_.DisplayName -match 'Surface UEFI'}

if ($InstalledApp){
    Write-Host "Warning: $($InstalledApp.DisplayName) is already installed with version $($InstalledApp.DisplayVersion)" -ForegroundColor Yellow
    Write-Host "Version to be installed is: " (($MSIFile.Name -Split 'v') -split '_')[3] -ForegroundColor Yellow
    }

# Install the MSI
Write-Host "`n====================================================================================" -ForegroundColor Gray
Write-Host "Starting MSI installation with command line:" -ForegroundColor Cyan
Write-Host "Start-Process `"msiexec.exe`" -ArgumentList `"/i `"$($MSIFile[0].FullName)`" /qn /L*V `"c:\windows\temp\SurfaceUEFI_MSI_$LogDate.log`"`"" -ForegroundColor Cyan
$MSIInstall = Start-Process "msiexec.exe" -ArgumentList "/i `"$($MSIFile[0].FullName)`" /qn /L*V `"c:\windows\temp\SurfaceUEFI_MSI_$LogDate.log`"" -Wait -PassThru
if ($MSIInstall.ExitCode -eq 0 -or $MSIInstall.ExitCode -eq 3010){
    Write-Host "The process exited with exit code $($MSIInstall.ExitCode)." -ForegroundColor Green
    }
else{
    Write-Host "The process exited with exit code $($MSIInstall.ExitCode)." -ForegroundColor Red
    }

# Remove the Start Menu Shortcut
if (Test-Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Surface UEFI Configurator.lnk"){
    Remove-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Surface UEFI Configurator.lnk" -Force
    }

# Checks for DLL to ensure it's there after install
Write-Host "`n====================================================================================" -ForegroundColor Gray
if (!(Test-Path "C:\ProgramData\Microsoft\Surface\Devices\SurfaceUefiManager.dll")){
    Write-Host "Warning: SurfaceUefiManager.dll was not found.  Script may error out." -ForegroundColor Red -BackgroundColor White
    }

else{
    [string]$DllVersion = (Get-Item "C:\ProgramData\Microsoft\Surface\Devices\SurfaceUefiManager.dll").VersionInfo.FileVersion
    Write-Host "SurfaceUefiManager.dll was found with version $($DllVersion)`n" -ForegroundColor Green
    }

# Loads the DLL into PowerShell Runspace 
Write-Host "Loading DLL into Memory..." -ForegroundColor Cyan
[System.Reflection.Assembly]::Load("SurfaceUefiManager, Version=$DllVersion, Culture=neutral, PublicKeyToken=fc3210b1ec5c11d4")

# Get Model of Surface and line it up with a package
Write-Host "`n====================================================================================" -ForegroundColor Gray
$uefi = [Microsoft.Surface.UefiManager]::CreateFromLocalDevice()
Write-Host "Manufacturer: " $uefi.Manufacturer -ForegroundColor Yellow
Write-Host "SystemFamily: " $uefi.SystemFamily -ForegroundColor Yellow
Write-Host "Model:        " $uefi.Model -ForegroundColor Yellow
Write-Host "Serial:       " $uefi.SerialNumber -ForegroundColor Yellow
Write-Host "UEFI Version: " $uefi.UefiVersion -ForegroundColor Yellow
Write-Host "SEMM Configuration Mechanism: " $uefi.ConfigurationMechanism -ForegroundColor Yellow

# Find the packages
Write-Host "`n====================================================================================" -ForegroundColor Gray
$OwnershipPackage = gci $scriptdir "*ProvisioningPackage.pkg"
$PermissionPackage = gci $scriptdir "$($uefi.Model) Permissions.pkg"
$SettingsPackage = gci $scriptdir "$($uefi.Model) Settings.pkg"
Write-Host "Ownership Package Found:   $($OwnerShipPackage.Name)" -ForegroundColor Green
Write-Host "Permissions Package Found: $($PermissionPackage.Name)" -ForegroundColor Green
Write-Host "Settings Package Found:    $($SettingsPackage.Name)" -ForegroundColor Green


# Apply the packages in the correct order
Write-Host "Applying Owner Permissions Package..." -ForegroundColor Yellow
$ownerPackageStream = New-Object System.IO.Filestream($OwnershipPackage.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
$sessionIdValue = $uefi.ApplySignerProvisioningPackage($ownerPackageStream)
$ownerSessionIdFile = Join-Path -Path $Scriptdir -ChildPath "OwnerSessionId.txt"
$writer = New-Object System.IO.StreamWriter($ownerSessionIdFile)
$writer.Write($sessionIdValue)
$writer.Close()
Write-Host "`tOwnership Package Applied.  Session ID Value: $sessionIdValue" -ForegroundColor Green

Write-Host "Applying Permissions Package..." -ForegroundColor Yellow
$permissionPackageStream = New-Object System.IO.Filestream($PermissionPackage.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
$sessionIdValue = $uefi.ApplyPermissionPackage($permissionPackageStream)
$permissionSessionIdFile = Join-Path -Path $Scriptdir -ChildPath "PermissionSessionId.txt"
$writer = New-Object System.IO.StreamWriter($permissionSessionIdFile)
$writer.Write($sessionIdValue)
$writer.Close()
Write-Host "`tPermissions Package Applied.  Session ID Value: $sessionIdValue" -ForegroundColor Green

Write-Host "Applying Settings Package..." -ForegroundColor Yellow
$uefi = [Microsoft.Surface.UefiManager]::CreateFromLocalDevice()
$settingsPackageStream = New-Object System.IO.Filestream($SettingsPackage.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
$sessionIdValue = $uefi.ApplySecuredSettingsPackage($settingsPackageStream)
$settingsSessionIdFile = Join-Path -Path $scriptdir -ChildPath "SettingsSessionId.txt"
$writer = New-Object System.IO.StreamWriter($settingsSessionIdFile)
$writer.Write($sessionIdValue)
$writer.Close()
Write-Host "`tSettings Package Applied.  Session ID Value: $sessionIdValue" -ForegroundColor Green

# Stop Logging
Write-Host "`nYou must reboot and enter 08 in the prompt that follows!!!" -ForegroundColor Green -BackgroundColor Black
Write-Host "You must reboot and enter 08 in the prompt that follows!!!" -ForegroundColor Green -BackgroundColor Black
Write-Host "You must reboot and enter 08 in the prompt that follows!!!" -ForegroundColor Green -BackgroundColor Black
Write-Host "You must reboot and enter 08 in the prompt that follows!!!" -ForegroundColor Green -BackgroundColor Black
Write-Host "You must reboot and enter 08 in the prompt that follows!!!`n" -ForegroundColor Green -BackgroundColor Black
Write-Host "That's ZERO EIGHT!!!`n" -ForegroundColor Green -BackgroundColor Black

Stop-Transcript

Write-Host "`nPress Enter to Exit the Script." -ForegroundColor Yellow
Read-Host