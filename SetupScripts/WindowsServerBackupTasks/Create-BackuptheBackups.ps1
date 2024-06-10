# ====================== CREATE TASK: BACKUP THE BACKUPS ======================
# Create or update a scheduled task to run WSB-BackuptheBackups.ps1.

# First look for an existing task using the old batch script and disable it
$oldTaskNames = @("Backup the backups", "Backup_the_backups", "backupthebackups")
Get-ScheduledTask | Where-Object {$oldTaskNames -contains $_.TaskName} | Disable-ScheduledTask

# Check for an existing task and delete it if found. This is needed in case 
# task schedule or other parameters have changed since the last update.
$taskName = "MITKY - Backup the Backups"
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Ignore

# Schedule for 30 minutes before Windows Server Backup start time
$wsbPolicy = Get-WBPolicy
$wsbTime = Get-WBSchedule -Policy $wsbPolicy
$taskTriggerTime = $wsbTime.AddMinutes(-30)
$taskTriggerTime = $taskTriggerTime.ToString("HH:mm")

$pathToScript = "C:\Scripts\RMMCustomMonitors\WindowsServerBackupScripts\WSB-BackuptheBackups.ps1"
$newTaskName = "MITKY - Backup the Backups"
$taskTrigger = New-ScheduledTaskTrigger -At $taskTriggerTime -Daily

# DO NOT CHANGE THESE VARIABLES
$arguments = "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $pathToScript"
$User = "NT AUTHORITY\SYSTEM"
$Action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument $arguments
$taskPath = "MayfieldIT"

# CREATES THE SCHEDULED TASK
Register-ScheduledTask -TaskName $newTaskName -Trigger $taskTrigger -User $User -Action $Action -RunLevel Highest -TaskPath $taskPath

# Checks that the task was created successfully and is active, and write the 
# result to the event log. An error should trigger an alert from an RMM monitor.
$newTask = Get-ScheduledTask -TaskName $newTaskName

if ($newTask.State -eq "Ready") {
  $params = @{
    LogName = "MITKY"
    Source = "RMM"
    EntryType = "Information"
    EventId = 109
    Message = "Task $newTaskName was created or updated successfully."
  }
  Write-EventLog @params
} else {
  $params = @{
    LogName = "MITKY"
    Source = "RMM"
    EntryType = "Error"
    EventId = 102
    Message = "Updating or creating task $newTaskName failed!"
  }
  Write-EventLog @params
}
