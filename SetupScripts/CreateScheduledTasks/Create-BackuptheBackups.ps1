# ====================== CREATE TASK: BACKUP THE BACKUPS ======================
# Create or update a scheduled task to run Maintenance-BackuptheBackups.ps1.

# First look for an existing task using the old batch script and disable it


# Check for an existing task and delete it if found. This is needed in case 
# Windows Server Backup schedule has changed since the last update.
$wsbStartTime = ""
$taskTriggerTime = ""


# Get Windows Server Backup schedule and set the task to run 30 minutes before





# Create the new task

$TaskName = "MITKY - Backup the Backups"
$Trigger = New-ScheduledTaskTrigger -At $taskTriggerTime -Daily
$User = "NT AUTHORITY\SYSTEM"
$Action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "C:\Scripts\RMMCustomMonitors\MaintenanceTaskScripts\BackuptheBackups.ps1"

Register-ScheduledTask -TaskName $TaskName -Trigger $Trigger -User $User -Action $Action