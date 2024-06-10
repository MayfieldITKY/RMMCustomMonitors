# =================== CREATE TASK: CHECK HYPER-V CHECKPOINTS ==================
# Create or update a scheduled task to run HOST-CheckHyperVCheckpoints.ps1.

# THIS IS ALWAYS NEEDED.
# Check for an existing task and delete it if found. This is needed in case 
# task schedule or other parameters have changed since the last update.
$taskName = "MITKY - Check Hyper-V Checkpoints"
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Ignore

# SPECIFY THESE VARIABLES
$pathToScript = "C:\Scripts\RMMCustomMonitors\HostServerScripts\HOST-CheckHyperVCheckpoints.ps1"
$newTaskName = "MITKY - Check Hyper-V Checkpoints"
$taskTriggerTime = "08:00"
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
