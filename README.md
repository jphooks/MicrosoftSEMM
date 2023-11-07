# IMPORTANT! Read me first!  Update 11/7/2023

The original scripts did not take into account the ConfigurationMechanism and UefiVersion.  Microsoft changed from V2 to V3.  Only V2 configuration files will work with V2 UEFI and only V3 configuration files will work with V3 UEFI.  This led to the generation and application scripts being completely reworked on our end.  At the moment, I do not have time to go through and cleanse the re-written scripts of company data so that they can be shared with the public.  If you are struggling to implement SEMM to a mixed environment and need help, feel free to reach out to me and I can do what I can to assist.  

| Model | UefiVersion |
| ------------- | ------------- |
| Surface Book | V2 |
| Surface Book 2 | V2 |
| Surface Book 3 | V2 |
| Surface Go | V2 |
| Surface Go 2 | V2 |
| Surface Go 3 | V3 |
| Surface Hub 2S | V3 |
| Surface Laptop | V2 |
| Surface Laptop 2 | V2 |
| Surface Laptop 3 | V2 |
| Surface Laptop 4 | V2 |
| Surface Laptop 5 | V3 |
| Surface Laptop Go | V2 |
| Surface Laptop Go 2 | V3 |
| Surface Laptop SE | V3 |
| Surface Laptop Studio | V3 |
| Surface Pro | V2 |
| Surface Pro 4 | V2 |
| Surface Pro 6 | V2 |
| Surface Pro 7 | V2 |
| Surface Pro 7+ | V2 |
| Surface Pro 8 | V3 |
| Surface Pro 9 | V3 |
| Surface Studio | V2 |
| Surface Studio 2 | V2 |
| Surface Studio 2+ | V3 |

# Implementing Microsoft Surface Enterprise Management Mode (SEMM)

We've been deploying Surface products since the original Surface Pro and we've always wanted to lock down the UEFI with a password programmatically while allowing the technician to change settings if they knew the password.  Microsoft made it challenging so I've always gotten close but never completed it.  I finally got it figured out and wanted to share my scripts and findings because there's so little out there to help folks. 

The [official MS documentation](https://docs.microsoft.com/en-us/surface/surface-enterprise-management-mode) makes it sound easy which it is if you want to lock down the entire UEFI.  You must create a certificate (either self-signed or using a domain certificate authority) and then use that cert with their Microsoft Surface UEFI Configurator program.  This program can give you an MSI which you can silently install on your surfaces.  The pro is it's easy to set up if you can get the certificate right.  The con is it locks everything down.  Every setting is greyed out and you either have to remove the cert to make changes or build another MSI using the same cert that can toggle the settings.  

PowerShell is required to fine tune everything just the way you want it and luckily I'm pretty good at PowerShell.  The problem is the SEMM documentation is very lacking and you have to go through each of the scripts provided by Microsoft and read every single comment to figure out what each line of code is doing.  It was exhausting but after several days of focusing 100% on it, I have a working product, and thought I would share since there's really so little out there on it.

Understanding the core concept of how it all works is important.  An IT Professional must obtain a certificate in PFX format that matches [Microsoft's requirements](https://docs.microsoft.com/en-us/surface/surface-enterprise-management-mode#surface-enterprise-management-mode-certificate-requirements).  This certificate can be used with PowerShell to create the following package files. 

* **Owner** - This is a universal package that will work on all Surface models to set the owner of the device
* **Permissions** - This is a package generated for each model that individually sets a permission on each setting
* **Settings** - This is a package generated for each model that modifies each setting
* **Universal Reset** - This is a package that will remove the certificate from any device configured with the same PFX.  

**Note:** The Universal Reset is a dangerous file to generate/use since it will work on any device.  MS recommends you generate a reset package per serial number so that if the reset file gets in the wrong hands it's only useful against 1 device in your fleet.  It's good to have a universal one though as long as you store it somewhere safe and only use it as a last resort.

You can then use these package files to configure your Surface devices.  You must do so in the correct order as outlined above.  You set the Owner first, then set the permissions, then modify the settings.  After that is complete, you reboot the surface and are asked to enter the last 2 characters of the certificate's thumbprint.  Then you're done.  The certificate is installed, the UEFI is locked behind a password, and the technician can change boot order or enable USB boot or whatever else they like since the local user is granted permissions.  My scripts do have the UEFI password locked to the owner though so a technician cannot remove or change the password.  

**IMPORTANT NOTE** - Removing the certificate from the UEFI does **NOT** remove the password or change any settings.  I had an issue where I set the UEFI password incorrectly and did not know what it was.  I thought "I'll just remove the certificate and it will go bye bye".  It didn't.  I tried to re-run my scripts and I could not inject a new certificate because it now requires the password to do so in addition to the last two characters of the thumbprint.  If I had left the certificate embedded, I could have used it to modify the password from Windows.  Luckily I was able to figure out the password but just wanted to mention it so someone doesn't run into the same issue.

**Generating the certificate** - This wasn't as bad as I thought it would be.  I didn't look into the self-signed route because we have an enterprise certificate authority.  I connected to my Server VM and loaded **certlm.msc** and went into the personal store.  I requested a new certificate, used the Server Certificate Template, gave it a Common Name of SEMM (CN=SEMM), a friendly name of SEMM 2022, and made the private key exportable.  All of the other MS requirements were default with our CA.  After the cert was generated, I simply exported it out of my personal computer store into a PFX file and was able to use it in the GUI and in the PowerShell scripts.

**Microsoft Downloads** - Go to the [Surface Tools for IT](https://www.microsoft.com/en-us/download/details.aspx?id=46703) and get the following files: 

* **SurfaceUEFI_Manager_v2.97.139.0_x64.msi** - The version number will change but this is the Microsoft Surface UEFI Configurator program mentioned above.  Installing this also installs the assemblies required to use the PowerShell commands.  This must be installed on the computer that generates the package files and it must also be installed on the Surface before it can apply the package files.  There may be a way to copy the DLL and other files from C:\ProgramData\Microsoft\Surface to avoid installing the MSI but it's pretty lightweight and quick to install.  I just make sure to remove the start menu shortcut from the Surface after applying the packages so users don't call in confused on what it's for.

* **SEMM_PowerShell.zip** - Optional - This contains all of the sample PowerShell scripts from Microsoft.  Their scripts aren't meant to actually be used in a production environment.  They're just samples so you can learn how to implement the product in your environment.

**My Scripts**

As mentioned, the first thing I had to do was create all of the Package files from my own laptop which is not a Surface product.  I wanted to do the configuration in a way where the PFX was protected as well as all passwords during deployment of the UEFI password and settings.  This seemed like the best method to implement the tool.  The PKG files can be edited in Notepad and you can see information in them (it's mostly XML) but I believe the important bits are encrypted.  The password value is 150 characters and is the same in all my setting files so I imagine it's a hash of some sort and may be able to be reverse engineered.  There may be a better way to do all of this but this is what's working for me and is as secure as I feel it can get.

**Here is the Package Generation script on Pastebin:** https://pastebin.com/Dvpn6PTB

**Here is a screenshot of the output:** https://i.imgur.com/3RkJkUY.jpg

If you scroll down to line 123 you can see where I go through each Surface model and set the configured values of each setting to the default value.  I also set the permission flag of each setting to both owner and local user.  You can change this if you like.  On line 134 you'll see where I enable the network stack if the configuration of that model supports it.  I do this because we use PXE in our environment to image devices with an SCCM Task Sequence.  I also disable USB boot.  On line 143, I set the UEFI password to the variable at the start of the script and set its permission to owner only which means you must use the certificate to change or remove the password.

After running the script, you will have a folder in your script root directory named after your certificate and then a large integer.  This integer is how many seconds have passed since 2000-01-01 and is used as the LowestSupportedVersion in the Pacakge XML.  Once the package is used, you cannot run an older package on the device, and this integer is how it determines if a package is newer or older.  It's not really important to understand but wanted to explain the significance.

In the directory, you'll find the following files. 

* **CERTNAME.pfx** - This is your cert copied into the directory.  I wanted to do this so I had one folder that had everything so I could back it up somewhere secure. 
* **CERTNAME_ProvisioningPackage.pkg** - This is the universal Owner package that will work on any model you deploy it to. 
* **CERTNAME_ResetPackage.pkg** - This is the universal Reset package that will remove the certificate from any surface that uses the same cert.
* **CERTNAME_Thumbprint.txt** - This is the Thumbprint of the cert saved in a text file so you won't ever forget the last two characters needed.
* **Surface Model Permissions.pkg** - This is the permissions package for each model supported by this tool
* **Surface Model Settings.pkg** - This is the settings package for each model supported by this tool

The next script I'll share is the one you'll want to run on the Surface itself to modify the UEFI and embed the certificate.  

**Here is the Modify UEFI and Set Password script on Pastebin:** https://pastebin.com/rB7j6nvY

**Here is a screenshot of the output:** https://i.imgur.com/sqZ5bLG.jpg

To start, you want to make a folder and copy the following files into it.  

* **CERTNAME_ProvisioningPackage.pkg** - The file you just generated which is the universal owner package
* **Surface Model Permissions.pkg** - I had 23 Permission package files, 1 for each model generated from their DLL
* **Surface Model Settings.pkg** - Again I had 23 of these Settings package files, 1 for each model
* **SurfaceUEFI_Manager_v2.97.139.0_x64.msi** - As mentioned this needs to be installed on the Surface to get the assemblies
* **My PowerShell Script** - This is does all the heavy lifting

It's important to note that this isn't my automation script that will ultimately end up in the task sequence.  This is my test script that a tech will run on a machine for testing.  That's why I have so much outputting to the screen.  I also have it logging to c:\windows\temp though so the transcript can be read later if necessary.  

The script performs the following tasks: 

1. Looks in the script root directory for the files you copied
2. Installs the MSI you put in the folder so the PowerShell assemblies can be used
3. Removes the start menu shortcut to the tool to keep it hidden from the end user
4. Loads the DLL and detects what model the Surface is
5. Matches the model with Permission and Settings files from the script root
6. Applies the universal Ownership package, the model specific Permissions package, and the model specific Settings package.
7. The sessionIDValues from applying the packages are output into text files into the script root directory.  This was something in the samples and I don't think it's important to keep in production but I didn't see the harm in keeping it.
8. At the end of the script I have a wall of text pop up to remind the technician what numbers to enter after a reboot.  You can change or remove this entirely.  
9. Make sure you remove the Read-Host if you plan on using this in automation as the script will hang without anyone to press enter at the very end.  

I typically drop a BAT file in the same directory as the PS1 file with the exact same name.  The contents of the BAT file are: 

    PowerShell.exe -NoProfile -Command "& {Start-Process PowerShell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dpn0.ps1""' -Verb RunAs}"

This allows a technician to just double click the BAT file and it will automatically open up PowerShell, prompting to run as administrator, and will execute the PowerShell script with the execution policy being bypassed.  I do this because it saves me the headache of having to explain how to do all of that and they can simply double click and go.  The read-host at the end prevents the window from disappearing so they can notice any errors.

When I add this to our task sequence I'll remove the read-host and also add some registry values that show what certificate was used and what "version" the package was.  Microsoft recommends doing this so you can then scan the registry keys for reporting later to determine which Surfaces you added the certificate and UEFI settings to.  I guess there's no WMI class you can inventory with SCCM for this so you'd have to build one yourself.  

**Here is the Universal Reset Script on Pastebin:** https://pastebin.com/TdZfMTiv

Simply copy this script and your CERTNAME_ResetPackage.pkg into the same folder and run it with administrative permissions.  It will apply the reset package and remove the certificate.  There is no end user input necessary to remove the cert.  In my tests, after a reboot, the cert is gone but the password will still be there and the settings will still be set to what you had them previously.  You can go in and remove the password though b/c the cert is no longer forcing that to "owner only".  

**Bonus Script - Export all Settings and Permissions to CSV on Pastebin:** https://pastebin.com/PNks7W50

I wrote this one to pull all of the settings and permissions after configuring them with the first script I shared.  If you run this in the same PowerShell runspace, you will get a CSV that shows all of the supported models, each setting and it's configured value, and the permissions you set on it.  I thought this would be important to save in the folder with everything else so I had a quick reference to the settings I configured and the UEFI password set and whatnot.  This does put the UEFI password in plain text so make sure you protect this file!  

============================================

Okay guys that's it for now.  I apologize for the wall of text but I wanted to be thorough.  I do love my job and learning and the best part is sharing what I learned with others.  I spent way too many hours wrapping my head around all of this and there were virtually no guides out there other than the MS scripts and comments.  Hopefully this has been helpful to someone.
