# COPY this template script for creating new monitoring and maintenance tasks.

# ====================== CREATE TASK: TASK NAME ======================
# Create or update a scheduled task to run <Task script>.ps1.

# USE THIS TO DISABLE ANY OBSOLETE TASKS. COMMENT IF NOT NEEDED.
# First look for an existing task using the old batch script and disable it
# $oldTaskNames = @("possible task name", "other task name", "task_name_could_be_this")
# Get-ScheduledTask | Where-Object {$oldTaskNames -contains $_.TaskName} | Disable-ScheduledTask

# THIS IS ALWAYS NEEDED.
# Check for an existing task and delete it if found. This is needed in case 
# task schedule or other parameters have changed since the last update.
$taskName = "MITKY - <TASK NAME>"
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Ignore

# USE THIS SECTION FOR PARAMETERS THAT MUST BE GENERATED PROGRAMMATICALLY.
# EXAMPLE: SCHEDULING AROUND WINDOWS SERVER BACKUP SCHEDULE.
# $wsbPolicy = Get-WBPolicy
# $wsbTime = Get-WBSchedule -Policy $wsbPolicy
# $taskTriggerTime = $wsbTime.AddMinutes(-30)
# $taskTriggerTime = $taskTriggerTime.ToString("HH:mm")

# SPECIFY THESE VARIABLES
$pathToScript = "C:\FULL\PATH\TO\SCRIPT.ps1"
$newTaskName = "MITKY - <TASK NAME>"
$taskTriggerTime = "HH:mm"
$taskTrigger = -At $taskTriggerTime -Daily # Other trigger types can be used

# DO NOT CHANGE THESE VARIABLES
$arguments = "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $pathToScript"
$User = "NT AUTHORITY\SYSTEM"
$Action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument $arguments
$taskPath = "Mayfield IT"

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
