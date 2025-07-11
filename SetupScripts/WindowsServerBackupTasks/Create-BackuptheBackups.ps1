# ====================== CREATE TASK: BACKUP THE BACKUPS ======================
# Create or update a scheduled task to run WSB-BackuptheBackups.ps1.

# First look for an existing task using the old batch script and disable it
$oldTaskName = "*backup*the*backups*"
Get-ScheduledTask | Where-Object {$_.TaskName -like $oldTaskName} | Disable-ScheduledTask

# DEFINE THESE VARIABLES
$pathToScript = "C:\Scripts\RMMCustomMonitors\WindowsServerBackupScripts\WSB-BackuptheBackups.ps1"
$newTaskName = "MITKY - Backup the Backups"
$newTaskDescription = @"
Renames backup revisions with date and rotates revisions if needed. 
Failed backups will also be removed. 
This runs before any scheduled backup. If backups do not run on weekends, 
this should also run after Friday's backup.
"@

# =============================================================================
# DO NOT CHANGE BELOW THIS LINE
$arguments = "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $pathToScript"
$User = "NT AUTHORITY\SYSTEM"
$Action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument $arguments
$taskPath = "MayfieldIT"
$startTime = $env:backup_the_backups_time
$taskTriggers = @()

$weekendBackup = $false
if ($env:weekend_backup -eq "TRUE") {$weekendBackup = $true}
If ($weekendBackup) {
    $taskTrigger = New-ScheduledTaskTrigger -Daily -At $startTime
    $taskTriggers += $taskTrigger
} 
Else {
    $taskTrigger1 = New-ScheduledTaskTrigger -Weekly -At $startTime -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday
    $saturdayTime = Get-Date $((Get-Date $startTime).AddHours(12)) -Format "HH:mm"
    $taskTrigger2 = New-ScheduledTaskTrigger -Weekly -At $saturdayTime -DaysOfWeek Saturday
    $taskTriggers += $taskTrigger1, $taskTrigger2
}


$newTaskParams = @{
  TaskName = $newTaskName
  Description = $newTaskDescription
  TaskPath = $taskPath
  Action = $Action
  User = $User
  RunLevel = "Highest"
  Trigger = $taskTriggers
}

# DELETE EXISTING TASK AND CREATE NEW TASK
Unregister-ScheduledTask -TaskName $newTaskName -Confirm:$false -ErrorAction Ignore
Register-ScheduledTask @newTaskParams

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
