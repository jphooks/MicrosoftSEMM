###############################################################################
# This script must be run on a Surface you wish to reset to remove the cert   #
###############################################################################

cls

# Set the script directory whether it's ran from ISE or not
if ($PSScriptRoot){$scriptdir = $PSScriptRoot}
else{$scriptdir = Split-Path -Path $psISE.CurrentFile.FullPath}

# Checks for DLL to ensure it's there before loading
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

# Gets the current model
$uefi = [Microsoft.Surface.UefiManager]::CreateFromLocalDevice()

# Find the reset package
$resetPackage = gci $scriptdir "*ResetPackage.pkg"

# Apply the reset package
Write-Host "`nApplying reset package - $($resetpackage.fullname)" -ForegroundColor Cyan
$resetPackageStream = New-Object System.IO.Filestream($resetPackage.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
$sessionIdValue = $uefi.ApplySignerProvisioningPackage($resetPackageStream)
Write-Host "`nReset Package Applied.  Session ID Value: $sessionIDValue" -ForegroundColor Green

# Exit script
Write-Host "`nYou must Reboot to finish. Press Enter to exit script." -ForegroundColor Yellow
Read-Host