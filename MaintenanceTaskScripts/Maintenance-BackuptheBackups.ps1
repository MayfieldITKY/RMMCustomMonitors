# ================ MAINTENANCE TASK: BACKUP THE BACKUPS ==================
# Creates and rotates revisions of Windows Server Backups on host servers.
# Checks that the recent backup is successful before updating revisions.
# This should replace the old backup_the_backups.bat script that creates 
# revisions without checking for successful backup.


# Common variables
$wsbDrive = (Get-WBSummary).LastBackupTarget
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
      Source = "Maintenance Tasks"
      EntryType = "Error"
      EventId = 8101
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
    Source = "Maintenance Tasks"
    EntryType = "Critical"
    EventId = 8100
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
    Source = "Maintenance Tasks"
    EntryType = "Error"
    EventId = 8102
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
}

# Reduce the number of revisions if needed.
If (-Not($enoughSpace)) {
  Remove-Item -Path $wsbDrive\$oldestRevision -Force -Recurse
  $wsbRevisions = Get-ChildItem $wsbDrive -Directory | Where-Object {($_.Name -like "WindowsImageBackup") -or ($_.Name -like "WindowsImageBackup_old*")}
  $howManyRevisions = $wsbRevisions.Length
  $oldestRevision = $wsbRevisions | Sort-Object LastWriteTime | Select-Object -First 1

  $params = @{
    LogName = "MITKY"
    Source = "Maintenance Tasks"
    EntryType = "Warning"
    EventId = 8104
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
    Source = "Maintenance Tasks"
    EntryType = "Error"
    EventId = 8103
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
    Source = "Maintenance Tasks"
    EntryType = "Information"
    EventId = 8109
    Message = "Backup revisions were successfully rotated.
    "
    }
    Write-EventLog @params
    exit
}
