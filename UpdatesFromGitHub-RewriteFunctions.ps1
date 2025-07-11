<#
================ Deploy Server Monitoring and Maintenance Tasks ===============
============================ Mayfield IT Consulting ===========================
====================== Updated 04/25/2025 by Jason Farris =====================
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
$hostname = $env:COMPUTERNAME
$client = $env:ShortSiteName
$runDate = Get-Date
$updateDate = Get-Date -Format "yyyyMMdd"
$updateTempPath = "C:\Scripts\Temp\$updateDate-RMMCustomMonitors"
$updateFileName = "RMMCustomMonitors.zip"
$updateFilePath = "$updateTempPath\$updateFileName"
$scriptsDestination = "C:\Scripts\RMMCustomMonitors"
$updateRepo = "test"
if ($env:updateRepository) {$updateRepo = $env:updateRepository}
$updateRepoFileName = "$updateRepo.zip"


# =============================== MAIN FUNCTION ===============================
function main {
    # Start log file
    New-UpdateLogFile
    Write-UpdateLogAndOutput @"
================ Deploy Server Monitoring and Maintenance Tasks ===============
============================ Mayfield IT Consulting ===========================
====================== Updated 04/25/2025 by Jason Farris =====================

Deployment run on: $runDate
Deploying branch: $updateRepo

"@ -NoTimestamp

# ============================== CREATE EVENT LOG =============================
    # Creates custom event log for RMM monitoring and maintenance scripts. This is
    # the custom event log that the RMM monitors will check. IF THIS DOESN'T WORK 
    # THEN NO RMM MONITORS WILL WORK!
    Write-UpdateLogAndOutput "Creating or updating custom event log..."
    New-EventLog -LogName MITKY -Source 'Scheduled Tasks', 'Maintenance Tasks', 'RMM' -ErrorAction Ignore
    Get-WinEvent -ListLog MITKY

    # Create custom view
    $customViewFilterXml = @"
<ViewerConfig>
    <QueryConfig>
        <QueryParams>
            <Simple>
                <Channel>MITKY</Channel>
                <RelativeTimeInfo>0</RelativeTimeInfo>
                <BySource>False</BySource>
            </Simple>
        </QueryParams>
        <QueryNode>
            <Name>MITKY</Name>
            <Description>Mayfield IT custom events</Description>
            <QueryList>
                <Query Id="0">
                    <Select Path="MITKY">*</Select>
                </Query>
            </QueryList>
        </QueryNode>
    </QueryConfig>
</ViewerConfig>
"@

    $customViewFilePath = "C:\ProgramData\Microsoft\Event Viewer\Views\MITKY.xml"
    if (Test-Path $customViewFilePath) {Remove-Item -Path $customViewFilePath -Force}
    New-Item -Path $customViewFilePath -Force -Value $customViewFilterXml

# ================== DOWNLOAD REPOSITORY FILE TO TEMP FOLDER ==================
    # If the temp path already exists (it should not because it contains the current
    # date!), delete it. Create the temp path
    If (Test-Path $updateTempPath) {
        Write-UpdateLogAndOutput "Removing previous temp folder..."
        Remove-Item $updateTempPath -Recurse -Force
        Start-Sleep 10
    }
    If (-Not(Test-Path $updateTempPath)) {
        Write-UpdateLogAndOutput "Creating temp folder for download..."
        New-Item -ItemType Directory -Path $updateTempPath
        Start-Sleep 10
    }

    # Set TLS version and get file
    Write-UpdateLogAndOutput "Downloading current repository..."
    [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11"
    Invoke-WebRequest -Uri https://github.com/MayfieldITKY/RMMCustomMonitors/archive/refs/heads/$updateRepoFileName -outfile $updateFilePath
    Start-Sleep 10
    # Wait a while to download for slow connections
    # ($waitTries + 1) * 10 = total wait time in seconds
    $waitTries = 5
    $tries = 0
    while ($tries++ -lt $waitTries) {
        If (Test-Path $updateFilePath) {break}
        Write-UpdateLogAndOutput "Waiting for file download..."
        Start-Sleep 10
    }

    If (-Not (Test-Path $updateFilePath)) {
        Write-UpdateLogAndOutput "Could not download repository! Check that the branch named $updateRepo is correct and is uploaded."
        return "noDownload"
    }

    # Compare the downloaded file to the last update file. If they are the same, no update is needed
    Write-UpdateLogAndOutput "Checking if update is needed..."
    $updateHash = Get-FileHash $updateFilePath -Algorithm SHA256
    $updateNeeded = $true

    If (Get-ChildItem -Path C:\scripts -Attributes Directory | Where-Object {$_.Name -like "RMMCustomMonitors"}) {
        $lastUpdateHash = Get-Content -Path "$scriptsDestination\LastUpdateHash.txt"
        If ($lastUpdateHash -eq $updateHash.Hash) {$updateNeeded = $false}
        else {Write-UpdateLogAndOutput "There are updated files. Proceeding..."}
    }

    If (-Not($updateNeeded)) {
        Write-UpdateLogAndOutput "RMMCustomMonitors are already up to date. Exiting..."
        Remove-Item $updateTempPath -Recurse -Force
        return "noUpdates"
    }

# =============== EXTRACT DOWNLOAD AND COPY TO TARGET DIRECTORY ===============
    Write-UpdateLogAndOutput "Extracting files..."
    Expand-UpdatePackage $updateFilePath $updateTempPath
    Start-Sleep 10

    $updateRepository = Get-ChildItem $updateTempPath -Directory -Attributes !H
    $expandedArchive = Get-ChildItem $updateRepository.FullName -Directory -Attributes !H
    
    # Remove previous files and recreate directory
    Write-UpdateLogAndOutput "Deleting old files..."
    If (Test-Path $scriptsDestination -ErrorAction Ignore) {
        Remove-Item $scriptsDestination -Recurse -Force
        Start-Sleep 10
    }
    If (-Not(Test-Path $scriptsDestination -ErrorAction Ignore)) {
        New-Item -ItemType Directory -Path $scriptsDestination
        Start-Sleep 10
    }
    
    # Copy files
    Write-UpdateLogAndOutput "Copying files to $scriptsDestination..."
    foreach ($dir in $expandedArchive) {
        $dirDestination = "$scriptsDestination\$dir"
        $dirPath = $dir.FullName
        Copy-Item -Path $dirPath -Destination $dirDestination -Recurse -Force
        Start-Sleep 10
    }
    
    # Store the hash for this update so it can be compared to future updates
    Write-UpdateLogAndOutput "Storing update version..."
    Set-Content -Path "$scriptsDestination\LastUpdateHash.txt" -Value $updateHash.Hash -Force

# =========================== CREATE SCHEDULED TASKS ==========================
    # DISABLE scheduled tasks with name starting with "MITKY*"
    Write-UpdateLogAndOutput "Disabling previous tasks..."
    $mitkyTasks = Get-ScheduledTask -TaskName "MITKY*"
    foreach ($task in $mitkyTasks) {Disable-ScheduledTask $task}

    # Get a list of scripts in the RunFirst folder and run them in the correct order
    Write-UpdateLogAndOutput "Running priority setup scripts..."
    $runFirstPath = "$scriptsDestination\SetupScripts\RunFirst"
    $runFirstList = Get-Content -Path "$runFirstPath\runFirstList.txt"
    foreach ($line in $runFirstList) {
        if ($line -notlike "#*") {
            if (($line -like "*.ps1") -or ($line -like "*.bat") -or ($line -like "*.reg")) {
                if (-Not (Test-Path "$runFirstPath\$line" -ErrorAction Ignore)) {continue}
                else {
                    Write-UpdateLogAndOutput "Running $line..."
                    $scriptPath = "$runFirstPath\$line"
                    & $scriptPath
                }
            }
        }
    }

    # Get list of setup scripts and run each script. Scripts should check for
    # existing tasks and delete them before creating
    Write-UpdateLogAndOutput "Running setup scripts for scheduled tasks..."
    $setupScripts = Get-ChildItem -Path "$scriptsDestination\SetupScripts\*" -Recurse -Include *.ps1 | Where-Object {$_.FullName -notlike "*RunFirst*"}

    foreach ($script in $setupScripts) {
        Write-UpdateLogAndOutput "Running $script..."
        $scriptPath = $script.FullName
        & $scriptPath
    }

# ======================== CREATE ENVIRONMENT VARIABLES =======================
# Set or update environment variables such as Datto site variables or UDFs.
# DO NOT CREATE VARIABLES WITH NAMES IDENTICAL TO DATTO VARIABLES - INCLUDING
# CASE-INSENSITIVE MATCHES! For example: 'short_site_name' vs 'SHORT_SITE_NAME'
# is BAD, 'short_site_name' vs 'ShortSiteName' is GOOD.
# These should NEVER contain secrets!
    Set-CustomSystemVariable "short_site_name" $env:ShortSiteName # Abbreviated client name from Datto variable
    Set-CustomSystemVariable "weekend_backup" $env:WeekendBackup # Weekend backups needed from Datto variable

# ============================= CLEANUP TEMP FILES ============================
    # Delete temporary files
    Write-UpdateLogAndOutput "Update completed! Cleaning up temporary files and reporting results..."
    Remove-Item $updateTempPath -Recurse -Force
    return "updateFinished"

}

# ============================== DEFINE FUNCTIONS =============================
function Get-Timestamp {Get-Date -Format "MM/dd/yyyy HH:mm:ss"}

# Create the log file
function New-UpdateLogFile {
    Param(
        [Parameter(Mandatory= $false)]
        [string]$updateLogName = "UpdateServerMonitoringTasks",
        [Parameter(Mandatory= $false)]
        [string]$updateLogFilePath = "C:\Scripts\Logs"
    )

    if (-Not(Test-Path $updateLogFilePath)) {
        New-Item -Path $updateLogFilePath -ItemType Directory
    }
    $logDate = Get-Date -Format "yyyyMMdd-HHmm"
    $logFileName = "$($updateLogName)_$($client)_$($hostname)_$($logDate).txt"
    New-Item -Path $updateLogFilePath -Name $logFileName -ItemType File
    $script:updateLogFullName = "$updateLogFilePath\$logFileName"
}

# Write to log file and output
function Write-UpdateLogAndOutput {
    Param(
        [Parameter(Mandatory= $false)]
        [string]$message,
        [Parameter(Mandatory= $false)]
        [switch]$NoTimestamp
    )
    if (-Not ($message)) {
        Write-Output " "
        Add-Content -Path $updateLogFullName " "
        return
    }
    if ($NoTimestamp) {
        Write-Output $message
        Add-Content -Path $updateLogFullName $message
    } else {
        Write-Output "$(Get-Timestamp): $message"
        Add-Content -Path $updateLogFullName "$(Get-Timestamp): $message"
    }
} 

# Extract downloaded file: Extraction function uses .NET methods for compatibility
# with Powershell v4.0 on Server 2012R2
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Expand-UpdatePackage {
    param([string]$zipfile, [string]$outpath)
    if (-Not (Test-Path $zipfile)) {
        Write-UpdateLogAndOutput "The target package file does not exist!"
        return
    } else {[System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)}
}

# Create environment variables
function Set-CustomSystemVariable {
    Param(
        [Parameter(Mandatory= $true)]
        [string]$eVarName,
        [Parameter(Mandatory= $true)]
        [string]$eVarValue 
    )
    If (-Not (([System.Environment]::GetEnvironmentVariable($eVarName, "Machine")) -eq $eVarValue)) {
        [System.Environment]::SetEnvironmentVariable($eVarName,$eVarValue,[System.EnvironmentVariableTarget]::Machine)
    }
    [string]$newVarValue = "$([System.Environment]::GetEnvironmentVariable($eVarName, "Machine"))"
    If ($newVarValue -eq $eVarValue) {
        Write-UpdateLogAndOutput "System variable $eVarName successfully updated to $newVarValue"
    } else {
        Write-UpdateLogAndOutput "System variable $eVarName did not update correctly!"
    }
}

# =================== PERFORM TASKS AND REPORT TO EVENT LOG ===================
$resultMessage = ""
$reportParams = @{
    LogName = "MITKY"
    Source = "RMM"
    EntryType = ""
    EventId = ""
    Message = ""
}

switch (main) {
#switch ($(("noDownload","noUpdates","updateFinished","somethingElse") | Get-Random)) {
    "noDownload" {
        $reportParams.EntryType = "Error"
        $reportParams.EventID = 111
        $resultMessage = "FAILED to download repository file!"
    }
    "noUpdates" {
        $reportParams.EntryType = "Information"
        $reportParams.EventID = 113
        $resultMessage = "NO UPDATES available"
    }
    "updateFinished" {
        $reportParams.EntryType = "Information"
        $reportParams.EventID = 114
        $resultMessage = "Finished updating. Check individual tasks to confirm results!"
    }
    default {
        $reportParams.EntryType = "Error"
        $reportParams.EventID = 112
        $resultMessage = "Updates stopped for unknown reason!"
    }
}

$updateLogReport = Get-Content $updateLogFullName
$reportParams.Message = @"
$resultMessage

FULL REPORT FROM LOG FILE: $updateLogFullName

$updateLogReport

"@

Write-EventLog @reportParams
