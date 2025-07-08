Write-Output @"
================== Deploy Custom Server Monitors from GitHub ==================
============================ Mayfield IT Consulting ===========================
====================== Updated 04/15/2025 by Jason Farris =====================

"@


<#
======================== DO NOT RUN AS A SCHEDULED JOB! =======================

This script downloads a repository from GitHub. If the repository is ever
compromised, servers could be infected with malicious scripts! Only run this as
an immediate job when updates are needed.

This script is for deploying and updating custom server monitors and maintenance
tasks from a GitHub repository. Monitors and tasks run as scheduled tasks and
write the result to the MITKY event log. The RMM monitors for these events and
alerts when necessary.

When creating a deployment job, CONFIRM the branch name is correct in the 
updateRepository variable. CONFIRM that the line for $updateRepo points to this
variable and comment out or delete the line for testing.
#>


# ============ VARIABLES FOR TEMPORARY FILES AND SCRIPT DESTINATION ===========
# ========= DO NOT CHANGE IN RMM! Update the GitHub repository instead ========
$runDate = Get-Date
$updateDate = Get-Date -Format yyyyMMdd
$updateTempPath = "C:\Scripts\Temp\$updateDate-RMMCustomMonitors"
$updateFileName = "RMMCustomMonitors.zip"
$updateFilePath = "$updateTempPath\$updateFileName"
$scriptsDestination = "C:\Scripts\RMMCustomMonitors"
$updateRepo = $env:updateRepository
#$updateRepo = "test" # This is used only for testing during development
$updateRepoFileName = "$updateRepo.zip"

Write-Output @"
Deployment run on: $runDate
Deploying branch: $updateRepo
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
# Set TLS version and get file
Write-Output "Downloading current repository..."
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11"
Invoke-WebRequest -Uri https://github.com/MayfieldITKY/RMMCustomMonitors/archive/refs/heads/$updateRepoFileName -outfile $updateFilePath
Start-Sleep 10

# Compare the downloaded file to the last update file. If they are the same, no update is needed
Write-Output "Checking if update is needed..."
$updateHash = Get-FileHash $updateFilePath -Algorithm SHA256
$updateNeeded = $true

If (Get-ChildItem -Path C:\scripts -Attributes Directory | Where-Object {$_.Name -like "RMMCustomMonitors"}) {
    $lastUpdateHash = Get-Content -Path "$scriptsDestination\LastUpdateHash.txt"
    If ($lastUpdateHash -eq $updateHash.Hash) {$updateNeeded = $false}
    else {Write-Output "There are updated files. Proceeding..."}
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

# ============================== CREATE EVENT LOG =============================
# Creates custom event log for RMM monitoring and maintenance scripts. This is
# the custom event log that the RMM monitors will check. IF THIS DOESN'T WORK 
# THEN NO RMM MONITORS WILL WORK!
Write-Output "Creating or updating custom event log..."
New-EventLog -LogName MITKY -Source 'Scheduled Tasks', 'Maintenance Tasks', 'RMM' -ErrorAction Ignore
Get-WinEvent -ListLog MITKY

# ======================== CREATE ENVIRONMENT VARIABLES =======================
# Set or update environment variables such as Datto site variables or UDFs.
# DO NOT CREATE VARIABLES WITH NAMES IDENTICAL TO DATTO VARIABLES - INCLUDING
# CASE-INSENSITIVE MATCHES! For example: 'short_site_name' vs 'SHORT_SITE_NAME'
# is BAD, 'short_site_name' vs 'ShortSiteName' is GOOD.
# These should NEVER contain secrets!

function Set-CustomSystemVariable([string]$eVarName, [string]$eVarValue) {
    If (-Not (([System.Environment]::GetEnvironmentVariable($eVarName, "Machine")) -eq $eVarValue)) {
        [System.Environment]::SetEnvironmentVariable($eVarName,$eVarValue,[System.EnvironmentVariableTarget]::Machine)
    }
}
# Set these variables from Datto site variables
Set-CustomSystemVariable "short_site_name" $env:ShortSiteName # Abbreviated client name from Datto variable
Set-CustomSystemVariable "weekend_backup" $env:WeekendBackup # Weekend backups needed from Datto variable

# =========================== CREATE SCHEDULED TASKS ==========================
# DISABLE scheduled tasks with name starting with "MITKY*"
Write-Output "Disabling previous tasks..."
$mitkyTasks = Get-ScheduledTask -TaskName "MITKY*"
foreach ($task in $mitkyTasks) {Disable-ScheduledTask $task}

# Get a list of scripts in the RunFirst folder and run them in the correct order
$runFirstPath = "$scriptsDestination\SetupScripts\RunFirst"
$runFirstList = Get-Content -Path "$runFirstPath\runFirstList.txt"
foreach ($line in $runFirstList) {
    if ($line -notlike "#*") {
        if (($line -like "*.ps1") -or ($line -like "*.bat") -or ($line -like "*.reg")) {
            if (-Not (Test-Path "$runFirstPath\$line" -ErrorAction Ignore)) {continue}
            else {
                Write-Output "Running $line..."
                $scriptPath = "$runFirstPath\$line"
                & $scriptPath
            }
        }
    }
}

# Get list of setup scripts and run each script. Scripts should check for
# existing tasks and delete them before creating
Write-Output "Running setup scripts for scheduled tasks..."
$setupScripts = Get-ChildItem -Path "$scriptsDestination\SetupScripts\*" -Recurse -Include *.ps1 | Where-Object {$_.FullName -notlike "*RunFirst*"}

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

