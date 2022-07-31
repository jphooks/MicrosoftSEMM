#########################################################################################
###### RUN THIS IN THE SAME POWERSHELL ISE WINDOW AS THE GENERATE PKG FILES SCRIPT ######
###### YOU MUST RUN THE OTHER SCRIPT FIRST, THIS WILL DUMP SETTINGS INTO A CSV     ######
###### THE CSV WILL BE IN THE SCRIPT ROOT DIRECTORY                                ######
#########################################################################################

# Set the script directory whether it's ran from ISE or not
if ($PSScriptRoot){$scriptdir = $PSScriptRoot}
else{$scriptdir = Split-Path -Path $psISE.CurrentFile.FullPath}

# Empty array to pump items in 
$allresults = @()

# Go through each device and get the settings
foreach ($uefi IN $surfaceDevices.Values) {
    foreach ($item in $uefi.settings.values){
        if ($item.ConfiguredPermissionFlags -eq 128){
            $perm = "OwnerOnly"
            }
        elseif ($item.ConfiguredPermissionFlags -eq 129){
            $perm = "OwnerandLocalUser"
            }
        else{
            [string]$perm = $item.ConfiguredPermissionFlags
            }
    
        $obj = new-object psobject
        $obj | add-member noteproperty Device $uefi.SurfaceUefiFamily
        $obj | add-member noteproperty Group $item.GroupName
        $obj | add-member noteproperty Name $item.Name
        $obj | add-member noteproperty ConfiguredValue $item.ConfiguredValue
        $obj | add-member noteproperty Default $item.DefaultValue
        $obj | add-member noteproperty Permission $perm
        $obj | add-member noteproperty ID $item.ID
        $allresults += $obj
        }
    }

$allresults | export-csv "$scriptdir\AllSettings.csv" -NoTypeInformation