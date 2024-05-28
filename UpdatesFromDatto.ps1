Write-Output @"
================== Deploy Custom Server Monitors from Datto ===================
============================ Mayfield IT Consulting ===========================
====================== Updated 05/28/2024 by Jason Farris =====================

"@


<#
=========================== USE THE GITHUB VERSION! ===========================
This script must have updated files attached to the Datto component, which may
not be up to date. This should only be used for testing or if GitHub is not
working for some reason. Make sure to update the attached ZIP file!

Only run this as an immediate job when updates are needed.

This script is for deploying and updating custom server monitors and maintenance
tasks. Monitors and tasks run as scheduled tasks and write the result to the
MITKY event log. The RMM monitors for these events and alerts when necessary.
#>


# ============ VARIABLES FOR TEMPORARY FILES AND SCRIPT DESTINATION ===========
$runDate = Get-Date
$updateDate = Get-Date -Format yyyyMMdd
$updateTempPath = "C:\Scripts\Temp\$updateDate-RMMCustomMonitors"
$updateFileName = "RMMCustomMonitors.zip"
$updateFilePath = "$updateTempPath\$updateFileName"
$scriptsDestination = "C:\Scripts\RMMCustomMonitors"
$updateRepoFileName = "$updateRepo.zip"

Write-Output @"
Deployment run on: $runDate
Deployment files were attached to Datto component! Use the GitHub version if possible!
"@

# If the temp path already exists (it should not because it contains the current
# date!), delete it. Create the temp path
If (Test-Path $updateTempPath) {
    Write-Output "Removing previous temp folder..."
    Remove-Item $updateTempPath -Recurse -Force
    Start-Sleep 10
}
If (-Not(Test-Path $updateTempPath)) {
    Write-Output "Creating temp folder for download..."
    New-Item -ItemType Directory -Path $updateTempPath
    Start-Sleep 10
}


# ================== DOWNLOAD REPOSITORY FILE TO TEMP FOLDER ==================
# Copy package from Datto to temp path
Write-Output "Getting current files from Datto..."
$updatePackage = ".\RMMCustomMonitors.zip"
Copy-Item -Path $updatePackage -Destination $updateFilePath
Start-Sleep 10

# Compare the downloaded file to the last update file. If they are the same, no update is needed
Write-Output "Checking if update is needed..."
$updateHash = Get-FileHash $updateFilePath -Algorithm SHA256
$updateNeeded = $true

If (Get-ChildItem -Path C:\scripts -Attributes Directory | Where-Object {$_.Name -like "RMMCustomMonitors"}) {
    $lastUpdateHash = Get-Content -Path "$scriptsDestination\LastUpdateHash.txt"
    If ($lastUpdateHash -eq $updateHash.Hash) {$updateNeeded = $false}
    Write-Output "There are updated files. Proceeding..."
}

If (-Not($updateNeeded)) {
    Write-Output "RMMCustomMonitors are already up to date. Exiting..."
    Remove-Item $updateTempPath -Recurse -Force
    # Need to report to event log here!
    exit
}


# ============= EXTRACT DOWNLOAD AND COPY TO TARGET DIRECTORY ===========
# Extraction function uses .NET methods for compatibility with Powershell
# v4.0 on Server 2012R2
Write-Output "Extracting files..."
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip {
    param([string]$zipfile, [string]$outpath)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

Unzip $updateFilePath $updateTempPath
Start-Sleep 10

$updateRepository = Get-ChildItem $updateTempPath -Directory -Attributes !H
$expandedArchive = Get-ChildItem $updateRepository.FullName -Directory -Attributes !H

# Remove previous files and recreate directory
Write-Output "Deleting old files..."
If (Test-Path $scriptsDestination -ErrorAction Ignore) {
    Remove-Item $scriptsDestination -Recurse -Force
    Start-Sleep 10
}
If (-Not(Test-Path $scriptsDestination -ErrorAction Ignore)) {
    New-Item -ItemType Directory -Path $scriptsDestination
    Start-Sleep 10
}

# Copy files
Write-Output "Copying files to $scriptsDestination..."
foreach ($dir in $expandedArchive) {
    $dirDestination = "$scriptsDestination\$dir"
    $dirPath = $dir.FullName
    Copy-Item -Path $dirPath -Destination $dirDestination -Recurse -Force
    Start-Sleep 10
}

# Store the hash for this update so it can be compared to future updates
Write-Output "Storing update version..."
Set-Content -Path "$scriptsDestination\LastUpdateHash.txt" -Value $updateHash.Hash -Force


# =========================== CREATE SCHEDULED TASKS ==========================
# Creates custom event log for RMM monitoring and maintenance scripts. This is
# the custom event log that the RMM monitors will check. IF THIS DOESN'T WORK 
# THEN NO RMM MONITORS WILL WORK!
Write-Output "Creating or updating custom event log..."
New-EventLog -LogName MITKY -Source 'Scheduled Tasks', 'Maintenance Tasks', 'RMM' -ErrorAction Ignore
Get-WinEvent -ListLog MITKY

# DISABLE scheduled tasks with name starting with "MITKY*"
Write-Output "Disabling previous tasks..."
$mitkyTasks = Get-ScheduledTask -TaskName "MITKY*"
foreach ($task in $mitkyTasks) {Disable-ScheduledTask $task}

# Get list of setup scripts and run each script. Scripts should check for
# existing tasks and delete them before creating
Write-Output "Running setup scripts for scheduled tasks..."
$setupScripts = Get-ChildItem -Path "$scriptsDestination\SetupScripts\*" -Recurse -Include *.ps1

foreach ($script in $setupScripts) {
    Write-Output "Running $script..."
    $scriptPath = $script.FullName
    & $scriptPath
}


# ============================= CLEANUP AND REPORT ============================
# Delete temporary files
Write-Output "Update completed! Cleaning up temporary files and reporting results..."
Remove-Item $updateTempPath -Recurse -Force

# Write to event log (not yet implemented)
