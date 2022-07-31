###############################################################################
# This script will create a bunch of PKG files used for configuring Surfaces  #
###############################################################################

############################
##### VARIABLES TO SET #####
############################

### THIS CERT MUST BE IN THE SCRIPT ROOT DIRECTORY TO WORK ###

# Change the Cert Name Here 
$certName = "CERT_NAME.pfx"

# Set the PFX password
$password = "CERT_PASSWORD"

# Set the password you want for the Surface UEFI when applied
$UEFIPassword = "UEFI_PASSWORD"

############################################################################
# Don't modify anything below this line unless you know what you're doing! #
############################################################################

# Set the script directory whether it's ran from ISE or not
if ($PSScriptRoot){$scriptdir = $PSScriptRoot}
else{$scriptdir = Split-Path -Path $psISE.CurrentFile.FullPath}

# Seconds from 2000-01-01 for the "tatooing" of the package file
$year2000 = New-Object -TypeName "System.DateTime" -ArgumentList 2000,1,1
$year2000Utc = $year2000.ToUniversalTime()
$timeDiff = [System.DateTime]::UtcNow - $year2000Utc
$lsv = [System.Convert]::ToInt64($timeDiff.TotalSeconds)
$certNameOnly = [System.IO.Path]::GetFileNameWithoutExtension($certName)
$dirname = "$scriptdir\$($certNameOnly)_$lsv"
$privateOwnerKey = Join-Path -Path $dirname -ChildPath $certName

# Write data to the screen
cls
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "Welcome to the Microsoft Surface Enterprise Management Mode creation tool!" -ForegroundColor Cyan
Write-Host "==========================================================================`n" -ForegroundColor Cyan

# Creates a subdirectory to store the cert and MSI files
if (Test-Path $dirname){
    Write-Host "Warning: Directory already exists!" -ForegroundColor Yellow
    Write-Host "`t$dirname`n" -ForegroundColor Yellow
    Write-Host "Are you sure you updated the Certificate name?" -ForegroundColor Yellow
    Write-Host "Pressing Enter will remove the directory and all files that reside in it." -ForegroundColor Red -BackgroundColor White
    Read-Host
    Remove-Item $dirname -Recurse -Force -Confirm:$false
    }
New-Item -ItemType Directory -Path $dirname | Out-Null
Copy-Item "$scriptdir\$certName" $dirname
Write-Host "Certificate copied to $dirname" -ForegroundColor Cyan

# Tests for DLL and exits if not found
if (!(Test-Path "C:\ProgramData\Microsoft\Surface\Devices\SurfaceUefiManager.dll")){
    Write-Host "Warning: SurfaceUefiManager.dll was not found.  Script cannot continue.  Ensure you installed the SurfaceUEFI_Configurator_x64.msi.  Press Enter to exit" -ForegroundColor Red -BackgroundColor White
    Read-Host
    Exit
    }

else{
    [string]$DllVersion = (Get-Item "C:\ProgramData\Microsoft\Surface\Devices\SurfaceUefiManager.dll").VersionInfo.FileVersion
    Write-Host "SurfaceUefiManager.dll was found with version $($DllVersion)`n" -ForegroundColor Green
    }

# Loads the DLL into PowerShell Runspace 
Write-Host "Loading DLL into Memory..." -ForegroundColor Cyan
[System.Reflection.Assembly]::Load("SurfaceUefiManager, Version=$DllVersion, Culture=neutral, PublicKeyToken=fc3210b1ec5c11d4")

# Get the latest versions for each device family.
Write-Host "`nLoading supported devices from DLL.`n" -ForegroundColor Cyan
$uefiManager = New-Object -TypeName Microsoft.Surface.UefiManager
$uefiManager.LoadKnownUefiConfigurations()
$surfaceDevices = @{}
foreach ($uefi in $uefiManager.SurfaceUefiConfigurations) {
   $surfaceDevices.Add($uefi.SurfaceUefiFamily, $uefi)
   Write-Host "Successfully loaded: $($uefi.SurfaceUefiFamily)" -ForegroundColor Green
   }
Write-Host ""

# Build the Owner Names, Reset Name, and Thumbprint Name
$ProvisioningPackage = $certNameOnly + "_ProvisioningPackage.pkg"
$ownerPackageName = Join-Path -Path $dirname -ChildPath $ProvisioningPackage

$ResetPackage = $certNameOnly + "_ResetPackage.pkg"
$resetPackageName = Join-Path -Path $dirname -ChildPath $ResetPackage

$ThumbName = $certNameOnly + "_Thumbprint.txt"
$certThumbName = Join-Path -Path $dirname -ChildPath $ThumbName

# Export the Certificate Thumbprint
$pw = ConvertTo-SecureString $password -AsPlainText -Force
$certPrint = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$certPrint.Import($privateOwnerKey, $pw, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
Write-Host "`nExporting Certificate Thumbprint.." -ForegroundColor Cyan
$certPrint.Thumbprint | Out-File $certThumbName
Write-Host "`tThumbprint exported to \$($certNameOnly)_$lsv\$ThumbName" -ForegroundColor Green

# Export the Master Ownership Package
Write-Host "`nBuilding Master Ownership File..." -ForegroundColor Cyan
$identity = [Microsoft.Surface.IUefiConfiguration+Identity]::SignerOwner
$stream = $uefi.BuildAndSignSignerProvisioningPackage($privateOwnerKey,$password,$privateOwnerKey,$password,$identity)
$signerProvisioningPackage = New-Object System.IO.Filestream($ownerPackageName, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
$stream.CopyTo($signerProvisioningPackage)
$signerProvisioningPackage.Close()
Write-Host "`tOwnership Package exported to \$($certNameOnly)_$lsv\$ProvisioningPackage" -ForegroundColor Green

# Export the Master Reset Package
Write-Host "`nBuilding Master Reset File..." -ForegroundColor Cyan
$stream = $uefi.BuildAndSignSignerProvisioningResetPackage($privateOwnerKey,$password,$identity)
$resetPackage = New-Object System.IO.Filestream($resetPackageName, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
$stream.CopyTo($resetPackage)
$resetPackage.Close()
Write-Host "`tReset Package exported to \$($certNameOnly)_$lsv\$ResetPackage`n" -ForegroundColor Green

# Setting Permissions
$ownerOnly = [Microsoft.Surface.IUefiSetting]::PermissionSignerOwner
$ownerAndLocalUser = ([Microsoft.Surface.IUefiSetting]::PermissionSignerOwner -bor [Microsoft.Surface.IUefiSetting]::PermissionLocal)

# Configure Settings and Permissions Packages for each model
foreach ($uefi IN $surfaceDevices.Values) {
    Write-Host "Configuring settings for $($uefi.SurfaceUefiFamily)" -ForegroundColor Cyan

    # Default all configured settings and set them to owner and local user so local user can modify settings
    foreach ($setting IN $uefi.Settings.Values) {
        #$setting.ClearConfiguredValue()
        $setting.ConfiguredValue = $setting.DefaultValue
        $setting.ConfiguredPermissionFlags = $ownerAndLocalUser
    }

    # Enable Network Stack for PXE and disable USB Boot if the model supports it
    if ($uefi.SettingsById[406]){
        $uefi.SettingsById[406].ConfiguredValue = "Enabled"
        }

    if ($uefi.SettingsById[403]){
        $uefi.SettingsById[403].ConfiguredValue = "Disabled"
        }

    # Set the UEFI password and force it to owner only so the cert is required to change the password
    $uefi.SettingsById[501].ConfiguredValue = $UEFIPassword
    $uefi.SettingsById[501].ConfiguredPermissionFlags = $ownerOnly

    # Create Package names for both Settings and Permissions
    $packageSettings = $uefi.SurfaceUefiFamily + " Settings.pkg"
    $packagePermissions = $uefi.SurfaceUefiFamily + " Permissions.pkg"
    $fullPackageNameSettings = Join-Path -Path $dirname -ChildPath $packageSettings
    $fullPackageNamePermissions = Join-Path -Path $dirname -ChildPath $packagePermissions

    # Build and sign the Settings package then save it to a file.
    $settingsPackageStream =  $uefi.BuildAndSignSecuredSettingsPackage($privateOwnerKey, $password, "", $null, $lsv)
    $settingsPackage = New-Object System.IO.Filestream($fullPackageNameSettings, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    $settingsPackageStream.CopyTo($settingsPackage)
    $settingsPackage.Close()
    Write-Host "`t$($uefi.Settings.Values.count) settings configured. Output file is in \$($certNameOnly)_$lsv\$packageSettings" -ForegroundColor Green

    # Build and sign the Permission package then save it to a file.
    $permissionPackageStream =  $uefi.BuildAndSignPermissionPackage($privateOwnerKey, $password, "", $null, $lsv)
    $permissionPackage = New-Object System.IO.Filestream($fullPackageNamePermissions, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    $permissionPackageStream.CopyTo($permissionPackage)
    $permissionPackage.Close()
    Write-Host "`tPermissions configured. Output file is in \$($certNameOnly)_$lsv\$packagePermissions`n" -ForegroundColor Green
}

Write-Host "                                                     "  -ForegroundColor White -BackgroundColor Black
Write-Host "  The last two characters of the thumbprint are" ($certPrint.Thumbprint.Substring($certPrint.Thumbprint.Length -2)) "  " -ForegroundColor White -BackgroundColor Black
Write-Host "                                                     "  -ForegroundColor White -BackgroundColor Black

Write-Host "`nAll Done!" -ForegroundColor Green