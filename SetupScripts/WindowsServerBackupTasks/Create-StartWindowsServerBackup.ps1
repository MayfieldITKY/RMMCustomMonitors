# ================ CREATE TASK: SCHEDULE WINDOWS SERVER BACKUP ================
# Create or update a scheduled task to schedule Windows Server Backup jobs. This
# is needed because backups cannot be scheduled for specific days of the week from
# the management console. Backups for most clients should run every weekday night.

# TASK VARIABLES
$taskName = "MITKY - Schedule Windows Server Backup"
$newTaskName = "MITKY - Start Windows Server Backup"
$backupStartTime = $env:backup_start_time
$pathToScript = "C:\Scripts\RMMCustomMonitors\WindowsServerBackupScripts\WSB-StartWindowsServerBackup.ps1"
$weekendBackup = $false

# If weekend backups are not needed, schedule backups for Monday-Friday only. If
# the schedule needs to be changed, it can be changed manually in the scheduled
# task. If this script is updated and run again, it should keep the new time.
if ($env:weekend_backup -eq "TRUE") {$weekendBackup = $true}
$taskTrigger = ""
If ($weekendBackup) {$taskTrigger = New-ScheduledTaskTrigger -Daily -At $backupStartTime} 
Else {$taskTrigger = New-ScheduledTaskTrigger -Weekly -At $backupStartTime -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday} 

# CREATE OTHER TASK PARAMETERS
# Task description should note the start time and if weekend backup is needed.
$descriptionWeekend = 'WEEKDAYS ONLY'
If ($weekendBackup) {$descriptionWeekend = 'EVERY DAY'}
$descriptionTime = Get-Date $backupStartTime -Format "h:mm tt"
$newTaskDescription = "Starts Windows Server Backup: $descriptionWeekend at $descriptionTime"

# DO NOT CHANGE THESE VARIABLES
$arguments = "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $pathToScript"
$User = "NT AUTHORITY\SYSTEM"
$Action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument $arguments
$taskPath = "MayfieldIT"

$newTaskParams = @{
  TaskName = $newTaskName
  Description = $newTaskDescription
  TaskPath = $taskPath
  Action = $Action
  User = $User
  RunLevel = "Highest"
  Trigger = $taskTrigger
}

# CREATES THE SCHEDULED TASK
# Check for an existing task and delete it if found. This is needed in case 
# task schedule or other parameters have changed since the last update.
# Remove Windows Server Backup schedule if the task creates successfully.
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Ignore
Unregister-ScheduledTask -TaskName $newTaskName -Confirm:$false -ErrorAction Ignore
Register-ScheduledTask @newTaskParams
$newTask = Get-ScheduledTask -TaskName $newTaskName
if ($newTask.State -eq "Ready") {Remove-WBPolicy -All -Force -ErrorAction Ignore}


# Checks that the task was created successfully and is active, and write the 
# result to the event log. An error should trigger an alert from an RMM monitor.
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
