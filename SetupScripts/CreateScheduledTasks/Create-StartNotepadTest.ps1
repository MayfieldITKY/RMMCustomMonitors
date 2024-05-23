# ====================== CREATE TASK: MITKY - Test Notepad ======================
# Create or update a scheduled task to run MITKY-TestNotepad.ps1.

# THIS IS ALWAYS NEEDED.
# Check for an existing task and delete it if found. This is needed in case 
# task schedule or other parameters have changed since the last update.
$taskName = "MITKY - Test Notepad"
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Ignore

# SPECIFY THESE VARIABLES
$pathToScript = "C:\Scripts\RMMCustomMonitors\ScheduledTaskScripts\MITKY-TestNotepad.ps1"
$newTaskName = "MITKY - Test Notepad"
$taskTriggerTime = (Get-Date).AddSeconds(60)
$taskTrigger = New-ScheduledTaskTrigger -Once -At $taskTriggerTime

# DO NOT CHANGE THESE VARIABLES
$arguments = "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $pathToScript"
$principal = New-ScheduledTaskPrincipal -GroupID "BUILTIN\Users"
$Action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument $arguments
$taskPath = "Mayfield IT"

# Create the scheduled task
Register-ScheduledTask -TaskName $newTaskName -Trigger $taskTrigger -Principal $principal -Action $Action -TaskPath $taskPath

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
