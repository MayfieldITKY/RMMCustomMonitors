# ====================== CREATE TASK: BACKUP THE BACKUPS ======================
# Create or update a scheduled task to run Maintenance-BackuptheBackups.ps1.


# First look for an existing task using the old batch script and disable it
$oldBackupTaskNames = @("backup the backups", "backup_the_backups", "backupthebackups")
Get-ScheduledTask | Where-Object {$oldBackupTaskNames -contains $_.TaskName} | Disable-ScheduledTask


# Check for an existing task and delete it if found. This is needed in case 
# Windows Server Backup schedule has changed since the last update.
$TaskName = "MITKY - Backup the Backups"
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false


# Get Windows Server Backup schedule and set the task to run 30 minutes before
$wsbPolicy = Get-WBPolicy
$wsbTime = Get-WBSchedule -Policy $wsbPolicy
$taskTriggerTime = $wsbTime.AddMinutes(-30)
$taskTriggerTime = $taskTriggerTime.ToString("HH:mm")


# Create the new task
$pathToScript = "C:\Scripts\RMMCustomMonitors\MaintenanceTaskScripts\Maintenance-BackuptheBackups.ps1"
$arguments = "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass –File $pathToScript"
$TaskName = "MITKY - Backup the Backups"
$taskTrigger = New-ScheduledTaskTrigger -At $taskTriggerTime -Daily
$User = "NT AUTHORITY\SYSTEM"
$Action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument $arguments

Register-ScheduledTask -TaskName $TaskName -Trigger $taskTrigger -User $User -Action $Action -RunLevel Highest