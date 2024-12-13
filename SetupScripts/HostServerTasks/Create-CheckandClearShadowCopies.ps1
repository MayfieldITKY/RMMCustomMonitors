# ================= CREATE TASK: CHECK AND CLEAR SHADOW COPIES ================
# Create or update a scheduled task to run HOST-CheckandClearShadowCopies.ps1.

# First look for an existing task using the old batch script and disable it
# $oldTaskNames = @("possible task name", "other task name", "task_name_could_be_this")
# Get-ScheduledTask | Where-Object {$oldTaskNames -contains $_.TaskName} | Disable-ScheduledTask

# Check for an existing task and delete it if found. This is needed in case 
# task schedule or other parameters have changed since the last update.
$taskName = "MITKY - Check and Clear Shadow Copies"
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Ignore

# SPECIFY THESE VARIABLES - Schedule 30 minutes before Windows Server Backup
$taskTriggerTime = "19:30" # Default to 7:30 PM if there is no other schedule
# If Windows Server Backup has previously run, use that time
if (Get-WBJob -Previous 1) {
    $lastBackupTime = [datetime]$((Get-WBJob -Previous 1 | Select-Object -Property StartTime).StartTime)
    $taskTriggerTime = $($lastBackupTime.AddMinutes(-30)).ToString("HH:mm")
} 
$pathToScript = "C:\Scripts\RMMCustomMonitors\HostServerScripts\HOST-CheckandClearShadowCopies.ps1"
$newTaskName = "MITKY - Check and Clear Shadow Copies"
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
