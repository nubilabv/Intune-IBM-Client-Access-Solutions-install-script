IBM i Access Client Solutions - Intune Deployment

PowerShell script to deploy IBM i ACS as a Win32 app in Intune, with optional preconfigured settings and session. ACS has no installer, so this does the work one would normally do: copy the files, apply config, set file associations, add a firewall rule, write a registry marker for detection. Associations go in HKLM, not HKCU. Intune runs Win32 apps as SYSTEM, so HKCU writes land in SYSTEM's hive and no real user ever sees them.

Prerequisites: Java. ACS won't launch without it - Make sure it's installed & build your Intune app with a dependency on your Java package. The ACS files from IBM. Not included here. IntuneWinAppUtil.exe for packaging.

Setup Drop the extracted ACS files next to Install-ACS.ps1 so the script's folder looks like this:

Install-ACS.ps1
AcsConfig.properties    (optional)
yoursession.hod               (optional)
Start_Programs\
... rest of the ACS payload

Edit the variables at the top of the script. At minimum change $DetectionRegPath (COMPANYNAME) and bump $DetectionRegValue whenever you repackage. Desktop shortcuts are commented out in step 4 - uncomment if you want them. AcsConfig.properties and AS400.hod are applied only if present, otherwise it warns and continues.

Package it:

IntuneWinAppUtil.exe -c "C:\path\to\ACS-Deploy" -s "Install-ACS.ps1" -o "C:\path\to\output"

Intune Install command:

powershell.exe -ExecutionPolicy Bypass -File .\Install-ACS.ps1

Install behaviour: System. Detection rule - Registry: Key: HKEY_LOCAL_MACHINE\SOFTWARE\COMPANYNAME\ACSDeployment Value: InstalledVersion Method: String comparison equals 1.0 - Bump both the script value and the detection rule (2.0, 3.0, ...) to push an update. Add Java as a required dependency.

Logs C:\ProgramData\ACSDeployment\Logs\Install-ACS_<timestamp>.log, one per run. First line tells you which account it ran as, usually the first thing you want to know when associations don't show up.

Notes .sql collides with SSMS, Azure Data Studio and VS Code. Drop it from $FileExtensions if your users have those. No uninstall script. Intune accepts the app without one, but you can't cleanly remove it from the portal.

HKLM sets the machine default association.

License MIT. Not affiliated with IBM. Made by Mirko - nubila.be
