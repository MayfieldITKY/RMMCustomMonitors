#$eventDetails = Import-Csv C:\Scripts\RMMCustomMonitors\ServerMonitorFunctions\EventDetails.csv
$eventDetails = Import-Csv "C:\Users\jfarris\OneDrive - Mayfield IT Consulting\Documents\GitHub\RMMCustomMonitors\TestDescriptions.csv"



# DEFINE FUNCTIONS
# Make timestamp
function Get-Timestamp {Get-Date -Format "MM/dd/yyyy HH:mm:ss"}

# Check if backup destination is a network path
function Get-ifNetworkLocation($destPath) {
    if (-Not($destPath)) {return $false}
    Elseif (Get-PSDrive $destPath -ErrorAction Ignore) {return $false}
    Elseif ($destPath -like "\\*") {return $true}
}

# Get information (hostname and folder) if backup location is a network path
function Get-NetworkLocationInfo($destPath) {
    $bupPath = ("$destPath".Replace('\\', ''))
    $bupPath = "$bupPath" -split '\\', 2
    return $bupPath[0], $bupPath[1]
}

# Get drive object if backup location is a network path
function Get-NetworkDrive($destPath) {
    $wsbDest = (Get-WmiObject -Class win32_share -ComputerName $wsbDestHostname | Where-Object {$_.Name -like "$wsbDestFolder"})
    $wsbDestDeviceID = ($wsbDest.Path).Replace("\","")
    $wsbDestDrive = (Get-WmiObject -Class Win32_LogicalDisk -ComputerName $wsbDestHostname | Where-Object {$_.DeviceID -like $wsbDestDeviceID})
    return $wsbDestDrive
}

# Rename a backup to append the client name and date
function Get-RevisionNewName($rev) {
    $revDate = Get-Date $rev.CreationTime -Format "yyyyMMdd-HHmm"    
    $revNewName = "$($client)_$($hostname)_WindowsImageBackup_$($revDate)"
    return $revNewName
}

function Rename-Backup($rev) {
    $revNewName = Get-RevisionNewName $rev
    if (-Not($rev.Name -like $revNewName)) {
        Write-LogAndOutput "Renaming revision: $($rev.Name)..."
        $rev | Rename-Item -NewName $revNewName
    }
}

# Calculate total space taken by a group of items, in GB
function Get-SpaceUsed($group) {
    $itemSizes = foreach ($item in $group) {Get-ChildItem $($item.FullName) -Recurse | Measure-Object -property length -sum}
    [int]$result = ($itemSizes.Sum | Measure-Object -Sum).Sum / 1GB
    return $result
}

# Check if an item takes an unexpected amount of space
function Get-IfWrongSize($item,[int]$expectedSize,[float]$margin) {
    $itemSize = Get-SpaceUsed $item
    [int]$min = $expectedSize / $margin
    [int]$max = $expectedSize * $margin
    if (($itemSize -lt $min) -or ($itemSize -gt $max)) {return $true}
    else {return $false}
}

# =============================================================================
# ====================== LOGGING AND REPORTING FUNCTIONS ======================
# =============================================================================

# Create a log file
function New-TaskLogFile {
    Param(
        [Parameter(Mandatory= $true)]
        [string]$taskLogName,
        [Parameter(Mandatory= $false)]
        [string]$taskLogFilePath = "C:\Scripts\Logs"
    )

    if (-Not(Test-Path $taskLogFilePath)) {
        New-Item -Path $taskLogFilePath -ItemType Directory
    }
    $logDate = Get-Date -Format "yyyyMMdd-HHmm"
    $logFileName = "$($taskLogName)_$($client)_$($hostname)_$($logDate).txt"
    New-Item -Path $taskLogFilePath -Name $logFileName -ItemType File
    $script:taskLogFullName = "$taskLogFilePath\$logFileName"
}

# Write to log file and output
function Write-LogAndOutput($message) {
    if (-Not ($message)) {
        Write-Output " "
        Add-Content -Path $taskLogFullName " "
        return
    }
    Write-Output "$(Get-Timestamp): $message"
    Add-Content -Path $taskLogFullName "$(Get-Timestamp): $message"
} 

# Look up Event Log parameters from file
function Get-EventParameters {
    Param(
        [Parameter(Mandatory= $true)]
        [string]$eventTaskName,
        [Parameter(Mandatory= $true)]
        [string]$eventTaskStatus
    )

    $targetEvent = $eventDetails | Where-Object {$_.TASKNAME -like "$($eventTaskName)" -and $_.STATUS -like "$($eventTaskStatus)"}
    if ($targetEvent) {return $targetEvent}
    else {return $false}
}





# Write the same message to the event log, log file, and output
function Write-ReportEvents {
    Param(
        [Parameter(Mandatory= $true)]
        [string]$eventTaskName,
        [Parameter(Mandatory= $true)]
        [string]$eventTaskStatus,

        # Only use these if the event parameters are not in the reference, but
        # it is strongly recommended to update the reference if possible instead
        # of including these parameters in the script.
        [Parameter(Mandatory= $false)]
        [string]$eventTaskEventID = 9999,
        [Parameter(Mandatory= $false)]
        [string]$eventTaskSource = "RMM",
        [Parameter(Mandatory= $false)]
        [string]$eventTaskType = "Warning",
        [Parameter(Mandatory= $false)]
        [string[]]$eventTaskDescription = ""
    )

    $targetEvent = Get-EventParameters -eventTaskName $eventTaskName -eventTaskStatus $eventTaskStatus
    if ($targetEvent) {
        $eventTaskEventID = $targetEvent.EVENTID
        $eventTaskSource = $targetEvent.SOURCE
        $eventTaskType = $targetEvent.TYPE
        $eventTaskDescription = $targetEvent.DESCRIPTION
    }
    if (-Not($eventTaskDescription)) {$eventTaskDescription = "A description was not provided for this event."}

    $params = @{
        LogName = "MITKY"
        Source = $eventTaskSource
        EntryType = $eventTaskType
        EventId = $eventTaskEventID
        Message = $eventTaskDescription
    }

    Write-EventLog @params
    Write-LogAndOutput $params.Message
}
