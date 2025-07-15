



# DEFINE FUNCTIONS
# Make timestamp
function Get-Timestamp {Get-Date -Format "MM/dd/yyyy HH:mm:ss"}

# Create the log file
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



<#
Task trigger based on event log

# Create a test task with the correct trigger and export it, then find the <Subscription> tag under <Triggers>
$triggerSubscription = @"
<QueryList><Query Id="0" Path="Microsoft-Windows-Backup">
<Select Path="Microsoft-Windows-Backup">*[System[Provider[@Name='Microsoft-Windows-Backup'] and EventID=4]]
</Select></Query></QueryList>
"@

$triggerDelay = "PT30M" # 30 minutes after trigger event

$triggerClass = Get-cimclass MSFT_TaskEventTrigger root/Microsoft/Windows/TaskScheduler
$taskTrigger = $triggerClass | New-CimInstance -ClientOnly
$taskTrigger.Enabled = $true
$taskTrigger.Subscription = $triggerSubscription
$taskTrigger.Delay = $triggerDelay

#>