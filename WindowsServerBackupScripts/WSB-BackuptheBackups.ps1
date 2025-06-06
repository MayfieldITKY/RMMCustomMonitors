# ===================== SCHEDULED TASK: BACKUP THE BACKUPS ====================
# Creates and rotates revisions of Windows Server Backups on host servers.
# Checks that the recent backup is successful before updating revisions.
# Checks that there is enough space for revisions and changes the number of
# revisions as needed (target is four revisions). This should replace the old
# backup_the_backups.bat script that creates revisions without checking for
# successful backup.

# COMMON VARIABLES
$client = $env:short_site_name # This is a Datto variable that is written to system ENV during deployment
$hostname = $env:COMPUTERNAME
$minimumNumberofRevisions = 4
$revisionGrowthFactor = 1.15 # use this multiplier to account for potential increase in backup size
$freeSpaceBuffer = 30 # use this amount (in GB) when calculating available space for revisions
$oldRevisionCutoff = -30 # revisions older than this many days are considered old. Use a negative number
$taskLogFilePath = "C:\Scripts\Logs"
$taskLogFullName = ""

# MAIN FUNCTION
function BackupTheBackups {
    # Start the log file
    New-TaskLogFile
    Write-LogAndOutput "Beginning task 'BACKUP THE BACKUPS' at $(Get-Date)..."

    # COMMON VARIABLES
    $wsbDrive = (Get-WBSummary).LastBackupTarget
    $wsbDriveName = $wsbDrive.Replace(":","")
    $wsbDestIsNetworkLocation = Get-ifNetworkLocation $wsbDrive
    $wsbDestHostname, $wsbDestFolder = "", ""
    if ($wsbDestIsNetworkLocation) {$wsbDestHostname, $wsbDestFolder = Get-NetworkLocationInfo $wsbDrive}    
    $wsbLastBackup = Get-ChildItem $wsbDrive -Directory | Where-Object {$_.Name -like "WindowsImageBackup"}
    if (-Not ($wsbLastBackup)) {$wsbLastBackup = Get-OldestRevision -1}
    $lastBackupSize = Get-SpaceUsed $wsbLastBackup
    $legacyRevisions = Get-ChildItem $wsbDrive -Directory | Where-Object {$_.Name -like "WindowsImageBackup_old*"}
    Write-LogAndOutput ""
    Write-LogAndOutput "Checking for protected revisions..."
    $protectedRevisions = Get-ProtectedRevisions
    if ($protectedRevisions) {foreach ($rev in $protectedRevisions) {Write-LogAndOutput $rev.FullName}}
    else {Write-LogAndOutput "No protected revisions found."}
    Write-LogAndOutput ""
    Write-LogAndOutput "Checking for old revisions. Confirm if these should be protected or deleted..."
    $veryOldRevisions = Get-OldRevisions
    if ($veryOldRevisions) {foreach ($rev in $veryOldRevisions) {Write-LogAndOutput $rev.FullName}}
    else {Write-LogAndOutput "No old revisions found."}
    Write-LogAndOutput ""
    Write-LogAndOutput "Checking for other data on the backup drive..."
    $nonBackupData = Get-ChildItem $wsbDrive | Where-Object {$_.Name -notlike "*WindowsImageBackup*"}
    if ($nonBackupData) {foreach ($item in $nonBackupData) {Write-LogAndOutput $item.FullName}}
    else {Write-LogAndOutput "No other data found."}
    [int]$wsbDriveSpace = Get-TotalSpace
    [int]$reservedSpace = Get-NonRevisionSpace
    $preferredNumberofRevisions = $minimumNumberofRevisions
    $expectedRevisionSize = Get-RevisionSize $(Get-CurrentRevisions)
    $expectedRevSizeSource = 'current'

    # DO THINGS
    # If there are no backup revisions at all, skip to checking free space.
    # If the last backup was successful, rename the backup with the date. If not,
    # rename it appending 'FAILED'. If the backup was already renamed, do nothing.
    if (-Not ($wsbLastBackup)) {}
    elseif ($wsbLastBackup.Name -eq "WindowsImageBackup") {
        function Rename-LastBackup() {
            if (Get-LastBackupSuccess) {Rename-Backup $wsbLastBackup}
            else {Rename-Backup $wsbLastBackup -Failed}
        }
        Rename-LastBackup
        Start-Sleep 3
        if (Test-Path $wsbLastBackup.FullName) {
            Rename-LastBackup
            Start-Sleep 3
            if (Test-Path $wsbLastBackup.FullName) {Write-ReportEvents 'renameLastBackupFailed'}
        }
    }

    # check if the last backup size is much larger or smaller than the expected revision size
    # if it is, also check it against the total current size of VHDs included in the backup
    # if the size of the backup is consistent with the size of VHDs, use the larger value for
    # the expected revision size. If not, use the total VHD size
    if (Get-IfWrongSize $wsbLastBackup $expectedRevisionSize $revisionGrowthFactor) {
        $vhdTotalSpace = Get-TotalSizeofVHDs
        $expectedRevisionSize = $vhdTotalSpace
        $expectedRevSizeSource = 'vhd'
        if (-Not (Get-IfWrongSize $wsbLastBackup $vhdTotalSpace $revisionGrowthFactor)) {
            if ($lastBackupSize -gt $vhdTotalSpace) {
                $expectedRevisionSize = $lastBackupSize
                $expectedRevSizeSource = 'last'
            }
        }
    } elseif ($lastBackupSize -gt $expectedRevisionSize) {
        $expectedRevisionSize = $lastBackupSize
        $expectedRevSizeSource = 'last'
    }

    # rename any legacy revisions (named with _old, _older, _oldest)
    if ($legacyRevisions) {
        Write-LogAndOutput ""
        Write-LogAndOutput 'Renaming revisions named with "_old, _older, _oldest" scheme...'
        foreach ($rev in $legacyRevisions) {Rename-Backup $rev}
    }

    # if there are not enough revisions and not enough space for them, determine 
    # if removing other data would help
    Write-LogAndOutput ""
    Write-LogAndOutput "Checking number of revisions..."
    if ((Get-CurrentNumberofRevisions) -lt $preferredNumberofRevisions) {
        Write-LogAndOutput "There are fewer than $preferredNumberofRevisions revisions. Checking revision size and free space..."
        if (((Get-FreeSpace) -lt ($expectedRevisionSize * $revisionGrowthFactor)) -and ($reservedSpace -gt 0)) {
            Write-LogAndOutput "There is not enough free space for another revision. Checking for non-backup data..."
            [int]$potentialSpace = (Get-FreeSpace) + $reservedSpace - $freeSpaceBuffer
            if ($potentialSpace -gt ($expectedRevisionSize * $revisionGrowthFactor)) {Write-ReportEvents 'excessiveNonBackupData'}
        }
    }

    # if there is not space for another revision, delete the oldest current
    # revision and update free space. Repeat until there is enough space
    # or only the last backup remains
    Write-LogAndOutput ""
    Write-LogAndOutput "Checking if there is enough free space for the next backup..."
    $targetFreeSpace = ($expectedRevisionSize * $revisionGrowthFactor) + $freeSpaceBuffer
    while ((Get-FreeSpace) -lt ($expectedRevisionSize * $revisionGrowthFactor)) {
        Write-LogAndOutput "Not enough free space for next backup. Need $targetFreeSpace GB free."
        if ($(Get-OldestRevision 1).Name -eq $(Get-OldestRevision -1).Name) {
            Write-ReportEvents 'notEnoughSpace'
            exit
        }
        Write-LogAndOutput "Deleting oldest revisions..."
        Write-LogAndOutput "Deleting revision: $((Get-OldestRevision 1).FullName)"
        if (-Not(Remove-Revision $(Get-OldestRevision 1))) {
            Start-Sleep 10
            if (-Not(Remove-Revision $(Get-OldestRevision 1))) {
                Write-ReportEvents 'deleteRevisionFailed'
                if ((Get-CurrentNumberofRevisions) -gt 2) {
                    Write-LogAndOutput "Deleting revision: $((Get-OldestRevision 2).FullName)"
                    if (-Not(Remove-Revision $(Get-OldestRevision 2))) {
                        Write-ReportEvents 'deleteRevisionFailed'
                        Write-ReportEvents 'notEnoughSpace'
                        exit
                    }
                } else {
                    Write-ReportEvents 'notEnoughSpace'
                    exit
                }
            }
        }
    }

    # report success - this should not trigger if there is a true failure. if the
    # last backup was successful, renamed correctly, and there is sufficient space
    # for a new backup, the task is successful.
    Write-LogAndOutput ""
    Write-ReportEvents 'success'
    
    $taskResults = @"
=== TASK RESULTS =======================
Task 'BACKUP THE BACKUPS' completed at $(Get-Date) for $hostname at $client.
The last backup was successful and renamed. There should be enough space for the next backup.
Most recent backup size (GB): $lastBackupSize

Backup drive total space (GB): $wsbDriveSpace
Backup drive free space (GB): $(Get-FreeSpace)
Backup revision expected size (GB): $expectedRevisionSize
Backup drive space that is NOT available for revisions (GB): $(Get-NonRevisionSpace)

There are $(Get-CurrentNumberofRevisions) current revisions. At least $preferredNumberofRevisions revisions are preferred.
======================= TASK COMPLETE =======================
"@
    Write-LogAndOutput ""
    Write-LogAndOutput $taskResults
    return
}

# DEFINE FUNCTIONS
# Make timestamp
function Get-Timestamp {Get-Date -Format "MM/dd/yyyy HH:mm:ss"}

# Create the log file
function New-TaskLogFile {
    if (-Not(Test-Path $taskLogFilePath)) {
        New-Item -Path $taskLogFilePath -ItemType Directory
    }
    $logDate = Get-Date -Format "yyyyMMdd-HHmm"
    $logFileName = "BackuptheBackupsLog_$($client)_$($hostname)_$($logDate).txt"
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

# Check if any backups exist
function Get-AllBackups {
    if (-Not(Test-Path $wsbDrive)) {
        Write-ReportEvents 'noBackupDrive'
        exit
    }
    $allBackups = Get-ChildItem $wsbDrive -Directory | Where-Object {$_.Name -like "*WindowsImageBackup*"}
    if (-Not($allBackups)) {
        Write-ReportEvents 'noRevisionsFound'
        exit
    }
    return $allBackups
}

# Check for successful backup
function Get-LastBackupSuccess {
    try {Get-WBSummary}
    catch {
        Write-ReportEvents 'noWindowsBackup'
        return $false
    }
    $LastWSBDate = (Get-WBSummary).LastBackupTime
    $LastDay = (Get-Date).AddHours(-24)
    $checkDate = $LastWSBDate
    if ($LastDay -lt $LastWSBDate) {$checkDate = $LastDay}
    $LastWSBSuccessEvent = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Backup'; StartTime=$checkDate; Id='4'}
    
    if (-Not($LastWSBSuccessEvent)) {
        Write-ReportEvents 'noBackupSuccess'
        return $false
    }      
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
    $revContent = Get-ChildItem $rev.FullName | Sort-Object LastWriteTime
    $revDate = Get-Date ($revContent[-1]).LastWriteTime -Format "yyyyMMdd-HHmm"    
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

# Check for protected revisions
function Get-ProtectedRevisions {
    $phrases = @("*do*not*delete*", "*don*t*delete*", "*delete*after*", "*keep*")
    $result = @()
    foreach ($bup in Get-AllBackups) {
        foreach ($p in $phrases) {
            if (-Not ($bup -in $result)) {
                if ($bup.Name -like $p) {$result += $bup}
            }
        }
    }
    return $result
}

# Check for very old revisions in case they should be protected
function Get-OldRevisions {
    $protectedRevisions = Get-ProtectedRevisions
    $cutoffDate = (Get-Date).AddDays($oldRevisionCutoff)
    $result = @()
    foreach ($bup in Get-AllBackups) {
        foreach ($pbup in $protectedRevisions) {
            if ($bup.Name -ne $pbup.Name) {
                if ($bup.CreationTime -lt $cutoffDate) {$result += $bup}
            }
        }
    }
    return $result
}

# Check that there are current revisions and count them
function Get-CurrentRevisions {
    $notCurrent = @()
    foreach ($bup in (Get-ProtectedRevisions)) {$notCurrent += "$($bup.Name)"}
    foreach ($bup in (Get-OldRevisions)) {$notCurrent += "$($bup.Name)"}
    $result = @()
    foreach ($bup in Get-AllBackups) {
        if (-Not($bup.Name -in $notCurrent)) {$result += $bup}
    }
    return $result
}

function Get-CurrentNumberofRevisions {return (Get-CurrentRevisions).Length}

# Calculate free space on backup drive
function Get-FreeSpace {
    [int]$free = 0
    if ($wsbDestIsNetworkLocation) {
        $destDrive = Get-NetworkDrive $wsbDrive
        [int]$free = $destDrive.FreeSpace / 1GB
    } else {[int]$free = (Get-PSDrive -Name $wsbDriveName).Free / 1GB}
    return $free
}

# Calculate total space on backup drive
function Get-TotalSpace {
    [int]$total = 0
    if ($wsbDestIsNetworkLocation) {
        $destDrive = Get-NetworkDrive $wsbDrive
        [int]$total = $destDrive.Size / 1GB
    } else {
    $used = (Get-PSDrive -Name $wsbDriveName).Used
    $free = (Get-PSDrive -Name $wsbDriveName).Free
    [int]$total = ($used + $free) / 1GB
    }
    return $total
}

# Calculate total space taken by a group of items
function Get-SpaceUsed($group) {
    $itemSizes = foreach ($item in $group) {Get-ChildItem $wsbDrive\$item -Recurse | Measure-Object -property length -sum}
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

# Calculate expected size of revisions
function Get-RevisionSize($group) {
    # First check if the group has only one item. if so, return its size
    if ($group.Count -eq 1) {return $(Get-SpaceUsed $group)}
    
    $revisionSizes = foreach ($rev in $group) {Get-ChildItem $wsbDrive\$rev -Recurse | Measure-Object -property length -sum}
    $revisionSizes = $revisionSizes | Sort-Object
    [int]$revisionSize = ($revisionSizes[[int]($revisionSizes.Count / 2)]).Sum / 1GB
    return $revisionSize
}

# Calculate space taken by non-backup data and protected revisions
function Get-NonRevisionSpace {
    [int]$reserved = 0
    $nonBupSpace = 0
    $protectedSpace = 0
    $oldSpace = 0

    if ($nonBackupData) {$nonBupSpace = Get-SpaceUsed $nonBackupData}
    if ($protectedRevisions) {$protectedSpace = Get-SpaceUsed $protectedRevisions}
    if ($veryOldRevisions) {$oldSpace = Get-SpaceUsed $veryOldRevisions}
    $reserved = $nonBupSpace + $protectedSpace + $oldSpace

    return $reserved
}

# Calculate the total current size of VHDs included in the backup
function Get-TotalSizeofVHDs {
    $backupVMs = Get-WBVirtualMachine | Where-Object {$_.VMName -notlike "Host Component"}
    $backupVHDs = @()
    foreach ($vm in $backupVMs) {
        $vm = Get-VM -Name $vm.VMName
        $disks = $vm.HardDrives | Where-Object {$_.Path -like "*.vhd*"}
        foreach ($d in $disks) {$backupVHDs += $d.Path}
    }
    $vhdSizes = foreach ($disk in $backupVHDs) {$(Get-ChildItem $disk).Length}
    [int]$vhdSizesTotal = (($vhdSizes | Measure-Object -Sum).Sum) / 1GB

    return $vhdSizesTotal
}

# Delete a revision
function Remove-Revision($rev) {
    $revPath = $rev.FullName
    $revDeleted = $false
    If (-Not(Test-Path $revPath -ErrorAction Ignore)) {return $true}
    Remove-Item -Path $revPath -Force -Recurse
    If (-Not(Test-Path $revPath -ErrorAction Ignore)) {$revDeleted = $true}
    Else {
        Start-Sleep 10
        If (-Not(Test-Path $revPath -ErrorAction Ignore)) {$revDeleted = $true}
    }

    return $revDeleted
}

# Get the oldest current revision
function Get-OldestRevision([int]$num) {
    $revs = Get-CurrentRevisions | Sort-Object CreationTime
    if ($num -lt 1) {$num += 1}
    return $revs[($num - 1)]
}

# Write results to event log
function Write-ReportEvents($status) {
    $params = @{
        LogName = "MITKY"
        Source = "Scheduled Tasks"
        EntryType = ""
        EventId = 0
        Message = ""
    }
    switch ($status) {
        'noBackupDrive' {
            $params.EntryType = "Error"
            $params.EventId = 2030
            $params.Message = "The backup drive was not found!"
        }
        'noRevisionsFound' {
            $params.EntryType = "Error"
            $params.EventId = 2031
            $params.Message = "No backup revisions were found! Check that Windows Server Backup is configured and the backup drive is healthy."
        }
        'noBackupSuccess' {
            $params.EntryType = "Error"
            $params.EventId = 2032
            $params.Message = "The last Windows Server Backup was not successful! No revisions were changed."
        }     
        'renameLastBackupFailed' {
            $params.EntryType = "Error"
            $params.EventId = 2033
            $params.Message = "The last Windows Server Backup revision could not be renamed! Check that the last backup has completed or if another process has the folder or files open."
        }
        'deleteRevisionFailed' {
            $params.EntryType = "Error"
            $params.EventId = 2034
            $params.Message = "Failed to delete previous revision! Check if it is open in another process."
        }
        'noWindowsBackup' {
            $params.EntryType = "Warning"
            $params.EventId = 2035
            $params.Message = "Windows Server Backup is not configured for this server or has not run."
        }   
        'excessiveNonBackupData' {
            $params.EntryType = "Warning"
            $params.EventId = 2036
            $params.Message = "There are not enough backup revisions present. Removing other data from the backup drive may free enough space for more revisions."
        }
        'notEnoughSpace' {
            $params.EntryType = "Error"
            $params.EventId = 2037
            $params.Message = "Could not create enough free space for the next backup! The next backup will most likely fail!"
        }
        'success' {
            $params.EntryType = "Information"
            $params.EventId = 2039
            $params.Message = "Backup revisions were checked and successfully rotated."
        }
    }
    Write-EventLog @params
    Write-LogAndOutput $params.Message
}

# CALL MAIN FUNCTION
BackupTheBackups
