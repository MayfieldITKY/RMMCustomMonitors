# ================ MAINTENANCE TASK: BACKUP THE BACKUPS ==================
# Creates and rotates revisions of Windows Server Backups on host servers.
# Checks that the recent backup is successful before updating revisions.
# This should replace the old backup_the_backups.bat script that creates 
# revisions without checking for successful backup.

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


If (-Not()) {
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


If (-Not()) {
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


# Check that there is enough space for revisions. If not, delete the oldest revision.
If (-Not()) {
  $params = @{
    LogName = "MITKY"
    Source = "Maintenance Tasks"
    EntryType = "Warning"
    EventId = 8103
    Message = "Not enough drive space for the scheduled number of revisions. The oldest revision was deleted."
  }
  Write-EventLog @params
  exit
}


# Rotate revisisons.

If () {
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
