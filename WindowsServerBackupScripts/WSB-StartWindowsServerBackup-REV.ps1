# ================= SCHEDULED TASK: START WINDOWS SERVER BACKUP ===============
# Starts a Windows Server Backup job.
# DEFINE VARIABLES AND FUNCTIONS
$hostname = $env:COMPUTERNAME
$client = $env:ShortSiteName

function Get-Timestamp {Get-Date -Format "MM/dd/yyyy HH:mm:ss"}

# Create the log file
function New-LogFile {
    Param(
        [Parameter(Mandatory= $false)]
        [string]$updateLogName = "StartWindowsServerBackup",
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
function Write-LogAndOutput {
    Param(
        [Parameter(Mandatory= $false)]
        [string]$message,
        [Parameter(Mandatory= $false)]
        [switch]$NoTimestamp
    )
    if (-Not ($message)) {
        Write-Output " "
        Add-Content -Path $updateLogFullName " "
    }
    elseif ($NoTimestamp) {
        Write-Output $message
        Add-Content -Path $updateLogFullName $message
    } else {
        Write-Output "$(Get-Timestamp): $message"
        Add-Content -Path $updateLogFullName "$(Get-Timestamp): $message"
    }
} 



# Start a log file
New-LogFile
Write-LogAndOutput @"
=================== SCHEDULED TASK: START WINDOWS SERVER BACKUP ===============
$(Get-Date | Out-String)
"@ -NoTimestamp
# First check for a backup policy defined by Windows Server Backup and remove it
if (Get-WBPolicy) {
    Write-LogAndOutput "Removing previously scheduled backup policy..."
    Remove-WBPolicy -All -Force -ErrorAction Ignore
} else {Write-LogAndOutput "No scheduled backup policy found."}
Write-LogAndOutput

# Create backup policy
$policy = New-WBPolicy
# Get all Hyper-V VMs, excluding any that are named with "test" or "-dbu" (for don't backup)
Write-LogAndOutput "Looking for virtual machines..."
$VMs = Get-WBVirtualMachine | Where-Object {($_.VMName -notlike "*test*") -and ($_.VMName -notlike "*-dbu")}
If ($VMs) {
    Write-LogAndOutput "The following VMs will be included in the backup:"
    foreach ($vm in $VMs) {Write-LogAndOutput "$($vm.VMName)" -NoTimestamp}
} else {
    Write-LogAndOutput "No VMs were found! Confirm this is running on a Hyper-V host and VMs are set up."
    Write-LogAndOutput "Exiting..."
    exit 1
} Write-LogAndOutput

# Find the last used backup drive or try to find a suitable drive
Write-LogAndOutput "Determining backup location..."
$lastBackupTarget = $(Get-WBSummary | Select-Object -Property LastBackupTarget).LastBackupTarget
if (-not ($lastBackupTarget)) {
    $lastBackupTarget = Get-PSDrive | Where-Object {($_.Provider -like "*FileSystem") -and (($_.Description -like "*Backup*") -or ($_.Description -like "*WSB*"))}
    if (-not ($lastBackupTarget)) {exit 1}
    $Script:backupLocation = New-WBBackupTarget -VolumePath $lastBackupTarget.Root
} else {$Script:backupLocation = New-WBBackupTarget -VolumePath $lastBackupTarget}
Write-LogAndOutput "Backup will be sent to $backupLocation"
Write-LogAndOutput

Add-WBBackupTarget -Policy $policy -Target $backupLocation
Add-WBVirtualMachine -Policy $policy -VirtualMachine $VMs
Write-LogAndOutput "Starting Windows Server Backup..."
Write-LogAndOutput
$backupReport = Start-WBBackup -Policy $policy
Write-LogAndOutput $backupReport -NoTimestamp
