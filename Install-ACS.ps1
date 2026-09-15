#Made by Mirko@nubila.be
#https://nubila.be

# This script is used to deploy IBM i Access Client Solutions (ACS) with preconfigured AcsConfig.properties (these properties are only needed when you want to deploy certain default settings/session)
# Used for Intune/SYSTEM-context deployment:
#   - File associations in HKLM (machine-wide) since this app runs as SYSTEM in intune, it writes to SYSTEM's own hive, not the user's)
#   - A registry marker written on success, for use as the Intune detection rule and for versioning

# Prerequisites
# Java needs to be installed, make sure to build your intune app with a dependency for this
# Have the iAccess Client Solution Files handy and ready to package with the script

# What this does
# Create a folder for installation
# Copy all files from the app to the install folder
# Applies custom configuration (if needed)
# Creates file associations (exclude sql if you need this for other apps)
# Creates desktop shortcuts (if needed)
# Creates firewall rules to allow the app
# Creates a registry entry to verify installation & version (for future updates)



# VARIABLES
$SourceFolder      = "$PSScriptRoot" #This assumes we include all the install files with the app
$TargetFolder      = "C:\Program Files (x86)\IBM\IBM i Access Client Solutions" #Change this folder to your desired install path
$LauncherExe       = "$TargetFolder\Start_Programs\Windows_x86-64\acslaunch_win-64.exe" 
$CustomConfigFile  = "$PSScriptRoot\AcsConfig.properties" #Exclude this if not needed
$FileExtensions    = @("hod", "dtfx", "dttx", "sql", "ws") #Needed for the file associations , edit where needed
$DetectionRegPath  = "HKLM:\SOFTWARE\COMPANYNAME\ACSDeployment"   # Change CompanyName (or change to something else)
$DetectionRegName  = "InstalledVersion"
$DetectionRegValue = "1.0"   # Bump this if you version your deployment package

# LOGGING
$logDir  = Join-Path $env:ProgramData "ACSDeployment\Logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir ("Install-ACS_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Output $line
    Add-Content -Path $logFile -Value $line
}

function New-DesktopShortcut {
    param([string]$ShortcutPath, [string]$TargetExe, [string]$Arguments, [string]$Description)
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $TargetExe
    if ($Arguments) { $Shortcut.Arguments = $Arguments }
    $Shortcut.Description = $Description
    $Shortcut.IconLocation = "$TargetExe,0"
    $Shortcut.Save()
}

function Set-FileAssociation {
    param([string]$Extension, [string]$ExePath)
    # HKLM, not HKCU: applies machine-wide, and is the right hive to write to when using system.
    $ProgId = "IBMiACS.$Extension"
    New-Item -Path "HKLM:\SOFTWARE\Classes\.$Extension" -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Classes\.$Extension" -Name "(Default)" -Value $ProgId
    New-Item -Path "HKLM:\SOFTWARE\Classes\$ProgId\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Classes\$ProgId\shell\open\command" -Name "(Default)" -Value "`"$ExePath`" `"%1`""
    Write-Log "Associated .$Extension with $ExePath"
}

# MAIN LOGIC
try {
    Write-Log "Starting IBM i Access Client Solutions deployment"
    Write-Log "Running as: $(whoami)"

    # 1. Copy files
    if (-not (Test-Path $TargetFolder)) {
        Write-Log "Creating target directory..."
        New-Item -ItemType Directory -Path $TargetFolder -Force | Out-Null
    }
    Write-Log "Copying ACS files from $SourceFolder to $TargetFolder..."
    Copy-Item -Path "$SourceFolder\*" -Destination $TargetFolder -Recurse -Force `
        -Exclude "Install-ACS.ps1"   # Don't copy the script into the install directory

    # 2. Apply AcsConfig.properties # Only needed if you are using the custom properties file, if not comment out this section or just leave as is, it will warn but continue
    if (Test-Path $CustomConfigFile) {
        Write-Log "Applying AcsConfig.properties..."
        Copy-Item -Path $CustomConfigFile -Destination "$TargetFolder\AcsConfig.properties" -Force
    } else {
        Write-Log "WARNING: AcsConfig.properties not found at $CustomConfigFile, skipping." "WARN"
    }

    # 3. Verify launcher exists before doing anything that depends on it
    if (-not (Test-Path $LauncherExe)) {
        throw "Launcher executable not found at $LauncherExe after copy -- deployment cannot continue."
    }

    # 4. Desktop shortcuts (Public Desktop,change if desired - we comment these out by default, not needed)
    #Write-Log "Creating desktop shortcuts..."
    #New-DesktopShortcut -ShortcutPath "$env:Public\Desktop\Access Client Solutions.lnk" ` #Comment this if you don't want the default icons
    #    -TargetExe $LauncherExe -Arguments "" -Description "IBM i Access Client Solutions" 
    #New-DesktopShortcut -ShortcutPath "$env:Public\Desktop\ACS Session Manager.lnk" ` #Comment this if you don't want the default icons
    #    -TargetExe $LauncherExe -Arguments "/plugin=sm" -Description "IBM i Access Client Solutions - Session Manager" #Comment this if you don't want the default icons

    # 5. File type associations (now machine-wide via HKLM)
    Write-Log "Associating file types..."
    foreach ($ext in $FileExtensions) {
        Set-FileAssociation -Extension $ext -ExePath $LauncherExe
    }

    # 6. Drop the custom connetion file to the public desktop #We use this to deploy a preconfigured session to the device, comment if not needed or change path.
    $hodSource = Join-Path $PSScriptRoot "xxx.hod" #Change to your custom HOD file
    if (Test-Path $hodSource) {
        Copy-Item $hodSource "C:\Users\Public\Desktop" -Force
        Write-Log "Copied custom HOD file to Public Desktop."
    } else {
        Write-Log "WARNING: xxx.hod not found at $hodSource, skipping." "WARN"
    }

    # 7. Allow ACS through Windows Firewall
    Write-Log "Creating Windows Firewall rule for ACS..."

    $ruleName = "Allow outbound - IBM i Access Client Solutions"

    if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Outbound `
        -Program $LauncherExe `
        -Action Allow `
        -Profile Any
    }




    # 8. Write a detection marker -- use this as both your detection rule and for future version upgrades, then change the detection rule to 2-3 etc...
    New-Item -Path $DetectionRegPath -Force | Out-Null
    Set-ItemProperty -Path $DetectionRegPath -Name $DetectionRegName -Value $DetectionRegValue

    Write-Log "Deployment completed successfully."
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)" "ERROR"
    exit 1
}
