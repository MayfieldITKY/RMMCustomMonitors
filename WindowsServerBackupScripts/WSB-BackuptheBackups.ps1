# ===================== SCHEDULED TASK: BACKUP THE BACKUPS ====================
# Creates and rotates revisions of Windows Server Backups on host servers.
# Checks that the recent backup is successful before updating revisions.
# Checks that there is enough space for revisions and changes the number of
# revisions as needed (target is four revisions). This should replace the old
# backup_the_backups.bat script that creates revisions without checking for
# successful backup.

# COMMON VARIABLES
#$client = $env:short_site_name -This is a Datto variable so we need a way to assign it to each host
$client = "TestClient"
$hostname = $env:COMPUTERNAME
$minimumNumberofRevisions = 4
$revisionGrowthFactor = 1.15
$freeSpaceBuffer = 30
$taskLogFilePath = "C:\Scripts\Logs"
$taskLogFullName = ""
$taskLogContent = @()

# MAIN FUNCTION
function BackupTheBackups {
    # Start the log file
    $taskLogFullName = "$(New-TaskLogFile)"
    Write-LogAndOutput "Beginning task 'BACKUP THE BACKUPS' at $(Get-Date)..."
    
    # CHECK FOR SUCCESSFUL BACKUP BEFORE DOING ANYTHING
    Get-LastBackupSuccess

    # COMMON VARIABLES
    $wsbDrive = (Get-WBSummary).LastBackupTarget
    $wsbDriveName = $wsbDrive.Replace(":","")
    $wsbLastBackup = Get-ChildItem $wsbDrive -Directory | Where-Object {$_.Name -like "WindowsImageBackup"}
    $legacyRevisions = Get-ChildItem $wsbDrive -Directory | Where-Object {$_.Name -like "WindowsImageBackup_old*"}
    Write-LogAndOutput "Checking for protected revisions..."
    $protectedRevisions = Get-ProtectedRevisions
    Write-LogAndOutput "Checking for old revisions. Confirm if these should be protected or deleted..."
    $veryOldRevisions = Get-OldRevisions
    Write-LogAndOutput "Checking for other data on the backup drive..."
    $nonBackupData = Get-ChildItem $wsbDrive | Where-Object {$_.Name -notlike "*WindowsImageBackup*"}
    [int]$wsbDriveSpace = Get-TotalSpace
    [int]$reservedSpace = Get-NonRevisionSpace
    [int]$spaceForRevisions = $wsbDriveSpace - $reservedSpace
    $preferredNumberofRevisions = $minimumNumberofRevisions
    $excessiveNonBackupData = $false

    # DO THINGS
    # try to rename last backup with client, hostname, and backup date
    Write-LogAndOutput "Renaming last backup..."
    try {Rename-Backup $wsbLastBackup}
    catch {
        Start-Sleep 10
        try {
            Rename-Backup $wsbLastBackup
            Start-Sleep 10
        }
        catch {
            Write-ReportEvents 'renameLastBackupFailed'
            exit
        }
    }

    # if there are not enough revisions and not enough space for them, determine 
    # if removing other data would help
    Write-LogAndOutput "Checking number of revisions..."
    if ((Get-CurrentNumberofRevisions) -lt $preferredNumberofRevisions) {
        $num = $preferredNumberofRevisions
        Write-LogAndOutput "There are fewer than $num revisions. Checking revision size and free space..."
        if (((Get-FreeSpace) -lt ((Get-RevisionSize) * $revisionGrowthFactor)) -and ($reservedSpace -gt 0)) {
            Write-LogAndOutput "There is not enough free space for another revision. Checking for non-backup data..."
            [int]$potentialSpace = (Get-FreeSpace) + $reservedSpace - $freeSpaceBuffer
            if ($potentialSpace -gt ((Get-RevisionSize) * $revisionGrowthFactor)) {
                $excessiveNonBackupData = $true
                Write-ReportEvents 'excessiveNonBackupData'
            }
        }
    }

    # if there is not space for another revision, delete the oldest current
    # revision and update free space. Delete two revisions if necessary
    Write-LogAndOutput "Checking if there is enough free space for the next backup..."
    if ((Get-FreeSpace) -lt ((Get-RevisionSize) * $revisionGrowthFactor)) {
        Write-LogAndOutput "Not enough free space for next backup. Deleting oldest revisions..."
        if(-Not(Remove-Revision $(Get-OldestRevision))) {Write-ReportEvents 'deleteRevisionFailed'}
        if ((Get-FreeSpace) -lt ((Get-RevisionSize) * $revisionGrowthFactor)) {
            if(-Not(Remove-Revision $(Get-OldestRevision))) {Write-ReportEvents 'deleteRevisionFailed'}
        }
    }

    # rename any legacy revisions (named with _old, _older, _oldest)
    if ($legacyRevisions) {
        Write-LogAndOutput 'Renaming revisions named with "_old, _older, _oldest" scheme...'
        foreach ($rev in $legacyRevisions) {Rename-Backup $rev}
    }

    # report success - this should not trigger if there is a true failure. If the
    # last backup was successful, renamed correctly, and there is sufficient space
    # for a new backup, the task is successful.
    Write-ReportEvents 'success'
    
    # collect statistics and write to the log file
    $legacyRevStats = "There were no revisions named with '_old, _older, _oldest' scheme."
    If ($legacyRevisions) {
        $legacyRevStats = "Renamed $(($legacyRevisions).Count) revisions named with '_old, _older, _oldest'"
    }
    $protectedRevStats = "There are no protected revisions."
    If ($protectedRevisions) {
        $protectedRevStats = @()
        $protectedRevStats += "There are $(($protectedRevisions).Count) protected revisions:"
        foreach ($rev in $protectedRevisions) {$protectedRevStats += "$($rev.FullName)"}
        $protectedRevStats += " "
    }
    $oldRevStats = "There are no old revisions to be reviewed."
    If ($veryOldRevisions) {
        $oldRevStats = @()
        $oldRevStats += "There are $(($veryOldRevisions).Count) old revisions to be reviewed:"
        foreach ($rev in $veryOldRevisions) {$veryOldRevisions += "$($rev.FullName)"}
        $oldRevStats += " "
    }
    $nonBupStats = "There is no additional data (not backups) on the backup drive."
    If ($nonBackupData) {
        $nonBupStats = @()
        $nonBupStats += "Additional data (not backups) was found on the backup drive. Consider moving or deleting this data:"
        foreach ($thing in $nonBackupData) {$nonBupStats += "$($thing.FullName)"}
        $nonBupStats += " "
    }


    $taskResults = @"
======================= TASK RESULTS =======================
Task 'BACKUP THE BACKUPS' completed at $(Get-Date) for $hostname at $client.
The last backup was successful and renamed. There should be enough space for the next backup.

Backup drive total space (GB): $wsbDriveSpace
Backup drive free space (GB): $(Get-FreeSpace)
Backup revision expected size (GB): $(Get-RevisionSize)
Backup drive space that is NOT available for revisions (GB): $(Get-NonRevisionSpace)

There are $(Get-CurrentNumberofRevisions) current revisions. At least $preferredNumberofRevisions revisions are preferred.
$legacyRevStats
$protectedRevStats
$oldRevStats
$nonBupStats
$(foreach ($bup in $nonBackupData) {"$bup.FullName"})

"@
    
    return
}



# DEFINE FUNCTIONS
# Make timestamp
function Get-Timestamp {Get-Date -Format "MM/dd/yyyy HH:mm:ss"}

# Create the log file
function New-TaskLogFile {
    If (-Not(Test-Path $taskLogFilePath)) {
        New-Item -Path $taskLogFilePath -ItemType Directory
    }
    $logDate = Get-Date -Format "yyyyMMdd-HHmm"
    $logFileName = "BackuptheBackupsLog_$($client)_$($hostname)_$($logDate).txt"
    New-Item -Path $taskLogFilePath -Name $logFileName
    $taskLogFullName = "$taskLogFilePath\$logFileName"

    If (Test-Path $taskLogFullName) {return $taskLogFullName}
}

# Write to log file and output
function Write-LogAndOutput($message) {
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
    if(-Not($allBackups)) {
        Write-ReportEvents 'noRevisionsFound'
        exit
    }

    return $allBackups
}

# Check for successful backup
function Get-LastBackupSuccess {
    Write-LogAndOutput "Checking if last backup was successful..."
    try {Get-WBSummary}
    catch {
        Write-ReportEvents 'noWindowsBackup'
        exit
    }

    $LastWSBDate = (Get-WBSummary).LastBackupTime
    $LastDay = (Get-Date).AddHours(-24)
    $checkDate = $LastWSBDate
    if ($LastDay -lt $LastWSBDate) {$checkDate = $LastDay}
    $LastWSBSuccessEvent = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Backup'; StartTime=$checkDate; Id='4'}
    
    If (-Not($LastWSBSuccessEvent)) {
        Write-ReportEvents 'noBackupSuccess'
        exit
    }      
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
    $cutoffDate = (Get-Date).AddDays(-7) # Do we use 7 or 14 days?
    $result = @()
    foreach ($bup in Get-AllBackups) {
        if ($bup -notin (Get-ProtectedRevisions)) {
            if ($bup.CreationTime -lt $cutoffDate) {$result += $bup}
        }
    }

    return $result
}

# Check that there are current revisions and count them
function Get-CurrentRevisions {
    $notCurrent = @()
    foreach ($bup in (Get-ProtectedRevisions)) {$notCurrent += "$($bup.Name)"}
    foreach ($bup in (Get-OldRevisions)) {$notCurrent += $bup}
    $result = @()
    foreach ($bup in Get-AllBackups) {
        if (-Not($bup.Name -in $notCurrent)) {$result += $bup}
    }

    return $result
}

function Get-CurrentNumberofRevisions {return (Get-CurrentRevisions).Length}

# Calculate expected size of revisions
function Get-RevisionSize {
    $revisionSizes = foreach ($rev in Get-CurrentRevisions) {Get-ChildItem $wsbDrive\$rev -Recurse | Measure-Object -property length -sum}
    [int]$revisionSize = ($revisionSizes.Sum | Measure-Object -Average).Average / 1GB
    return $revisionSize
}

# Calculate free space on backup drive
function Get-FreeSpace {
    [int]$free = (Get-PSDrive -Name $wsbDriveName).Free / 1GB
    return $free
}

# Calculate total space on backup drive
function Get-TotalSpace {
    $used = (Get-PSDrive -Name $wsbDriveName).Used
    $free = (Get-PSDrive -Name $wsbDriveName).Free
    [int]$total = ($used + $free) / 1GB
    return $total
}

# Calculate total space taken by a group of items
function Get-SpaceUsed($group) {
    $itemSizes = foreach ($item in $group) {Get-ChildItem $wsbDrive\$item -Recurse | Measure-Object -property length -sum}
    [int]$result = ($itemSizes.Sum | Measure-Object -Sum).Sum / 1GB
    return $result
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

# Determine number of revisions to keep (goal is four)
function Get-TargetNumberForRevisions {
    Write-LogAndOutput "Checking if additional revisions are needed..."
    $potentialRevisions = $currentNumberofRevisions
    if ($potentialRevisions -lt $preferredNumberofRevisions) {
        Write-LogAndOutput "Calculating space available for additional revisions..."
        $revsNeeded = $preferredNumberofRevisions - $potentialRevisions
        [int]$revsCanAdd = [Math]::Floor([decimal]((Get-FreeSpace) - 10) / ((Get-RevisionSize) * $revisionGrowthFactor))
        if ($revsCanAdd -gt $revsNeeded) {$revsCanAdd = $revsNeeded}
        $potentialRevisions = $potentialRevisions + $revsCanAdd
        Write-LogAndOutput "$($revsNeeded) additional revisions are needed. There is space for $($revsCanAdd) additional revisions."
    }

    return $potentialRevisions
}

# Delete a revision
function Remove-Revision($rev) {
    $revName = "$rev.Name"
    try {Remove-Item -Path $wsbDrive\$rev -Force -Recurse}
    catch {return $revName}
}

# Get the oldest current revision
function Get-OldestRevision {
    Get-CurrentRevisions | Sort-Object CreationTime | Select-Object -First 1
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
        'renameLastBackupFailed' {
            $params.EntryType = "Error"
            $params.EventId = 2032
            $params.Message = "The last Windows Server Backup revision could not be renamed! Check that the last backup has completed or if another process has the folder or files open."
        }
        'excessiveNonBackupData' {
            $params.EntryType = "Warning"
            $params.EventId = 2055
            $params.Message = "There are not enough backup revisions present. Removing other data from the backup drive may free enough space for more revisions."
        }
        'noBackupDrive' {
            $params.EntryType = "Error"
            $params.EventId = 2050
            $params.Message = "The backup drive was not found!"
        }
        'noRevisionsFound' {
            $params.EntryType = "Error"
            $params.EventId = 2030
            $params.Message = "No backup revisions were found! Check that Windows Server Backup is configured and the backup drive is healthy."
        }
        'noWindowsBackup' {
            $params.EntryType = "Warning"
            $params.EventId = 2010
            $params.Message = "Windows Server Backup is not configured for this server or has not run."
        }
        'noBackupSuccess' {
            $params.EntryType = "Error"
            $params.EventId = 2031
            $params.Message = "The last Windows Server Backup was not successful! No revisions were changed."
        }
        'deleteRevisionFailed' {
            $params.EntryType = "Error"
            $params.EventId = 2033
            $params.Message = "Failed to delete previous revision: $revName! Check if it is open in another process."
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


