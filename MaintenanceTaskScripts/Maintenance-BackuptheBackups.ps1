# ================ MAINTENANCE TASK: BACKUP THE BACKUPS ==================
# Creates and rotates revisions of Windows Server Backups on host servers.
# Checks that the recent backup is successful before updating revisions.
# This should replace the old backup_the_backups.bat script that creates 
# revisions without checking for successful backup.

# Check for successful backup. Do not change revisions if the most recent
# backup was not successful.
$LastWSBDate = (Get-Date).AddHours(-24)
$SuccessEvent = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Backup'; StartTime=$LastWSBDate; Id='4'}

If (-Not($SuccessEvent)) {
    $params = @{
      LogName = "MITKY"
      Source = "Maintenance Tasks"
      EntryType = "Information"
      EventId = 8101
      Message = "The last Windows Server Backup was not successful! No revisions were changed."
    }
    Write-EventLog @params
    exit
  }


# If the last backup was successful, attempt to rotate revisions:
# Check that the last backup can be renamed. If not, another process may have the
# folder or files open and revisions should not be rotated.


# Check that there is enough space for revisions. If not, delete the oldest revision.


# Rotate revisisons.



# Report results to the event log.