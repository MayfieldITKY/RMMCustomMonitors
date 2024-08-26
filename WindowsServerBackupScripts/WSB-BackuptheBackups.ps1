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


# MAIN FUNCTION
function BackupTheBackups {
    # CHECK FOR SUCCESSFUL BACKUP BEFORE DOING ANYTHING
    Get-LastBackupSuccess

    # COMMON VARIABLES
    $wsbDrive = (Get-WBSummary).LastBackupTarget
    $wsbDriveName = $wsbDrive.Replace(":","")
    $wsbLastBackup = Get-ChildItem $wsbDrive -Directory | Where-Object {$_.Name -like "WindowsImageBackup"}
    $legacyRevisions = Get-ChildItem $wsbDrive -Directory | Where-Object {$_.Name -like "WindowsImageBackup_old*"}
    $protectedRevisions = Get-ProtectedRevisions
    $veryOldRevisions = Get-OldRevisions
    $nonBackupData = Get-ChildItem $wsbDrive | Where-Object {$_.Name -notlike "*WindowsImageBackup*"}
    [int]$wsbDriveSpace = Get-TotalSpace
    [int]$reservedSpace = Get-NonRevisionSpace
    [int]$spaceForRevisions = $wsbDriveSpace - $reservedSpace
    $preferredNumberofRevisions = $minimumNumberofRevisions

    # DO THINGS
    # try to rename last backup with client, hostname, and backup date
    try {Rename-Backup $wsbLastBackup}
    catch {
        Start-Sleep 10
        try {
            Rename-Backup $wsbLastBackup
            Start-Sleep 10
        }
        catch {
            $params = @{
                LogName = "MITKY"
                Source = "Scheduled Tasks"
                EntryType = "Error"
                EventId = 2032
                Message = "The last Windows Server Backup revision could not be renamed! Check that the last backup has completed or if another process has the folder or files open."
            }
            Write-EventLog @params
            exit
        }
    }

    # if there are not enough revisions and not enough space for them, determine if removing other data would help
    if ((Get-CurrentNumberofRevisions) -lt $preferredNumberofRevisions) {
        if (((Get-FreeSpace) -lt ((Get-RevisionSize) * $revisionGrowthFactor)) -and ($reservedSpace -gt 0)) {
            [int]$potentialSpace = (Get-FreeSpace) + $reservedSpace - $freeSpaceBuffer
            if ($potentialSpace -gt ((Get-RevisionSize) * $revisionGrowthFactor)) {
                $params = @{
                    LogName = "MITKY"
                    Source = "Scheduled Tasks"
                    EntryType = "Warning"
                    EventId = 2055
                    Message = "There are not enough backup revisions present. Removing other data from the backup drive may free enough space for more revisions."
                }
                Write-EventLog @params
            }
        }
    }

    # if there is not space for another revision, delete the oldest current revision and update free space. Delete two revisions if necessary
    if ((Get-FreeSpace) -lt ((Get-RevisionSize) * $revisionGrowthFactor)) {
        Remove-OldestRevision
        if ((Get-FreeSpace) -lt ((Get-RevisionSize) * $revisionGrowthFactor)) {
            Remove-OldestRevision
        }
    }

    # rename any legacy revisions (named with _old, _older, _oldest)
    if ($legacyRevisions) {
        foreach ($rev in $legacyRevisions) {Rename-Backup $rev}
    }

    












}




# DEFINE FUNCTIONS
# Check if any backups exist
function Get-AllBackups {
    try {Get-ChildItem $wsbDrive}
    catch {
        $params = @{
            LogName = "MITKY"
            Source = "Scheduled Tasks"
            EntryType = "Critical"
            EventId = 2050
            Message = "The backup drive was not found!"
        }
        Write-EventLog @params
        exit
    }
    $allBackups = Get-ChildItem $wsbDrive -Directory | Where-Object {$_.Name -like "*WindowsImageBackup*"}
    if(-Not($allBackups)) {
        $params = @{
            LogName = "MITKY"
            Source = "Scheduled Tasks"
            EntryType = "Critical"
            EventId = 2030
            Message = "No backup revisions were found! Check that Windows Server Backup is configured and the backup drive is healthy."
        }
        Write-EventLog @params
        exit
    }

    return $allBackups
}

# Check for successful backup
function Get-LastBackupSuccess {
    If (-Not(Get-WBSummary)) {
        $params = @{
            LogName = "MITKY"
            Source = "Scheduled Tasks"
            EntryType = "Warning"
            EventId = 2010
            Message = "Windows Server Backup is not configured for this server."
        }
        Write-EventLog @params
        exit
    }

    $LastWSBDate = (Get-WBSummary).LastBackupTime
    $LastWSBSuccessEvent = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Backup'; StartTime=$LastWSBDate; Id='4'}
    
    If (-Not($LastWSBSuccessEvent)) {
        $params = @{
            LogName = "MITKY"
            Source = "Scheduled Tasks"
            EntryType = "Error"
            EventId = 2031
            Message = "The last Windows Server Backup was not successful! No revisions were changed."
        }
        Write-EventLog @params
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
    if (-Not($rev.Name -like $revNewName)) {$rev | Rename-Item -NewName $revNewName}
}

# Check for protected revisions
function Get-ProtectedRevisions {
    $phrases = @("*do not delete*", "*dont delete*", "*delete after*", "*keep*")
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
    foreach ($bup in (Get-ProtectedRevisions)) {$notCurrent += $bup}
    foreach ($bup in (Get-OldRevisions)) {$notCurrent += $bup}
    $result = @()
    foreach ($bup in Get-AllBackups) {
        $bupNotCurrent = $false
        if ($bup -in $notCurrent) {$bupNotCurrent = $true}
        if (-Not($bupNotCurrent)) {$result += $bup}
    }

    return $result
}

function Get-CurrentNumberofRevisions {return (Get-CurrentRevisions).Length}

# Calculate expected size of revisions
function Get-RevisionSize {
    $revisionSizes = foreach ($rev in Get-CurrentRevisions) {Get-ChildItem $wsbDrive\$rev -Recurse | Measure-Object -property length -sum}
    return ($revisionSizes.Sum | Measure-Object -Average).Average / 1GB
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
    [int]$result =  $itemSizes.Sum / 1GB
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
    $potentialRevisions = $currentNumberofRevisions
    if ($potentialRevisions -lt $preferredNumberofRevisions) {
        $revsNeeded = $preferredNumberofRevisions - $potentialRevisions
        [int]$revsCanAdd = Math.Truncate(((Get-FreeSpace) - 10) / ((Get-RevisionSize) * $revisionGrowthFactor))
        if ($revsCanAdd -gt $revsNeeded) {$revsCanAdd = $revsNeeded}
        $potentialRevisions = $potentialRevisions + $revsCanAdd
    }

    return $potentialRevisions
}

# Delete a revision
function Remove-Revision($rev) {
    try {Remove-Item -Path $wsbDrive\$rev -Force -Recurse}
    catch {
        $revName = $rev.Name
        $params = @{
            LogName = "MITKY"
            Source = "Scheduled Tasks"
            EntryType = "Error"
            EventId = 2033
            Message = "Failed to delete revision: $revName! Check if it is open in another process."
        }
        Write-EventLog @params
    }
}

# Delete the oldest current revision and update the current revisions list
function Remove-OldestRevision {
    $oldestRevision = Get-CurrentRevisions | Sort-Object CreationTime | Select-Object -First 1
    Remove-Revision $oldestRevision
}



# Write results to event log
function Get-ResultsReport {}




# CALL MAIN FUNCTION
BackupTheBackups



# =======================================================
# =======================================================
# =======================================================
# =======================================================
# =======================================================
# REFACTORING

$wsbRevisions = Get-ChildItem $wsbDrive -Directory | Where-Object {($_.Name -like "WindowsImageBackup") -or ($_.Name -like "WindowsImageBackup_old*")}
$howManyRevisions = $wsbRevisions.Length
$oldestRevision = $wsbRevisions | Sort-Object LastWriteTime | Select-Object -First 1



# Check for successful backup. Do not change revisions if the most recent
# backup was not successful.
$LastWSBDate = (Get-Date).AddHours(-24)
$LastWSBSuccessEvent = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Backup'; StartTime=$LastWSBDate; Id='4'}

If (-Not($LastWSBSuccessEvent)) {
    $params = @{
      LogName = "MITKY"
      Source = "Scheduled Tasks"
      EntryType = "Error"
      EventId = 2031
      Message = "The last Windows Server Backup was not successful! No revisions were changed."
    }
    Write-EventLog @params
    exit
  }


# Check that there are revisions. If not, Windows Server Backup may not be configured
# or there could be a problem with the backup drive.
If (-Not($wsbRevisions)) {
  $params = @{
    LogName = "MITKY"
    Source = "Scheduled Tasks"
    EntryType = "Critical"
    EventId = 2030
    Message = "No backup revisions were found! Check that Windows Server Backup is configured and the backup drive is healthy."
  }
  Write-EventLog @params
  exit
}


# Check that the last backup can be renamed. If not, another process may have the
# folder or files open and revisions should not be rotated.
$wsbLastBackupPath = Get-ChildItem $wsbDrive -Directory | Where-Object {$_.Name -like "WindowsImageBackup"}

try {
  Rename-Item -Path ($wsbLastBackupPath).FullName -NewName "WindowsImageBackupRename"
  Start-Sleep 5
  $wsbRenameBackupPath = Get-ChildItem $wsbDrive -Directory | Where-Object {$_.Name -like "WindowsImageBackupRename"}
  Rename-Item -Path ($wsbRenameBackupPath).FullName -NewName "WindowsImageBackup"
} 
catch { 
  $params = @{
    LogName = "MITKY"
    Source = "Scheduled Tasks"
    EntryType = "Error"
    EventId = 2032
    Message = "The last Windows Server Backup revision could not be renamed! Check that the last backup has completed or if another process has the folder or files open."
  }
  Write-EventLog @params
  exit
}


# Check that there is enough space for revisions. Do some math first: get average
# size of current revisions and get free space left on backup drive. If there are 
# less than four revisions, add one if there is room. If there may not be room for
# the current number of revisions, decrease the number of revisions by one.
$oldestRevision = $wsbRevisions | Sort-Object LastWriteTime | Select-Object -First 1
$protectOldestRevision = $false
$revisionSizes = foreach ($rev in $wsbRevisions) {Get-ChildItem $wsbDrive\$rev -Recurse | Measure-Object -property length -sum}
$revisionTypicalSize = ($revisionSizes.Sum | Measure-Object -Average).Average / 1GB
$wsbDriveFreeSpace = (Get-PSDrive -Name ($wsbDrive.Replace(":",""))).Free / 1GB
$enoughSpace = $false
If ($wsbDriveFreeSpace -gt ($revisionTypicalSize * 1.15)) {$enoughSpace = $true}

# Check if another revision is needed and add one if there is space.
If (($howManyRevisions -lt 4) -and ($wsbDriveFreeSpace -gt ($revisionTypicalSize * 2.3))) {
  $howManyRevisions += 1
  $protectOldestRevision = $true

  $params = @{
    LogName = "MITKY"
    Source = "Scheduled Tasks"
    EntryType = "Information"
    EventId = 2038
    Message = "There were less than four backup revisions. An additional revision was scheduled."
  }
  Write-EventLog @params
}

# Reduce the number of revisions if needed.
If (-Not($enoughSpace)) {
  Remove-Item -Path $wsbDrive\$oldestRevision -Force -Recurse
  $wsbRevisions = Get-ChildItem $wsbDrive -Directory | Where-Object {($_.Name -like "WindowsImageBackup") -or ($_.Name -like "WindowsImageBackup_old*")}
  $howManyRevisions = $wsbRevisions.Length
  $oldestRevision = $wsbRevisions | Sort-Object LastWriteTime | Select-Object -First 1

  $params = @{
    LogName = "MITKY"
    Source = "Scheduled Tasks"
    EntryType = "Warning"
    EventId = 2034
    Message = "Not enough drive space for the scheduled number of revisions. The oldest revision was deleted."
  }
  Write-EventLog @params
}


# Rotate revisisons.
try {
  If (-Not($protectOldestRevision)) {
    Remove-Item -Path $wsbDrive\$oldestRevision -Force -Recurse
  }
  Start-Sleep 10
  If ($howManyRevisions -gt 3) {
      Rename-Item $wsbDrive\WindowsImageBackup_older -NewName "WindowsImageBackup_oldest"
      Start-Sleep 10
  }
  If ($howManyRevisions -gt 2) {
      Rename-Item $wsbDrive\WindowsImageBackup_old -NewName "WindowsImageBackup_older"
      Start-Sleep 10
  }
  If ($howManyRevisions -gt 1) {
      Rename-Item $wsbDrive\WindowsImageBackup -NewName "WindowsImageBackup_old"
      Start-Sleep 10
  }
}
catch {
  $params = @{
    LogName = "MITKY"
    Source = "Scheduled Tasks"
    EntryType = "Error"
    EventId = 2033
    Message = "Failed to rotate divisions! Check if any revisions are open in another process."
  }
  Write-EventLog @params
  exit
}

# If rotation was successful and the number of revisions was not reduced,
# write success event to log MITKY.
If ($enoughSpace) {
  $params = @{
    LogName = "MITKY"
    Source = "Scheduled Tasks"
    EntryType = "Information"
    EventId = 2039
    Message = "Backup revisions were successfully rotated.
    "
    }
    Write-EventLog @params
    exit
}
