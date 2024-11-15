# ================ CREATE TASK: SCHEDULE WINDOWS SERVER BACKUP ================
# Create or update a scheduled task to schedule Windows Server Backup jobs. This
# is needed because backups cannot be scheduled for specific days of the week from
# the management console. Backups for most clients should run every weekday night.

# First check if Windows Server Backup is scheduled from the management console and
# if this server should run backups on the weekend. If so, do nothing and leave the
# current policy in place.



# If there is a policy but weekend backups are not needed, record the policy's start
# time as an environment variable so future backups will start at the same time. If
# the schedule needs to be changed, it can be changed in the scheduled task.



# If there is no policy, use the time from the current scheduled task. If there is
# no task, default to 8:00 PM. If weekend backups are not needed, schedule backups
# for Monday-Friday only.





# Check for an existing task and delete it if found. This is needed in case 
# task schedule or other parameters have changed since the last update.
$taskName = "MITKY - Schedule Windows Server Backup"
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Ignore

# USE THIS SECTION FOR PARAMETERS THAT MUST BE GENERATED PROGRAMMATICALLY.
# EXAMPLE: SCHEDULING AROUND WINDOWS SERVER BACKUP SCHEDULE.
# $wsbPolicy = Get-WBPolicy
# $wsbTime = Get-WBSchedule -Policy $wsbPolicy
# $taskTriggerTime = $wsbTime.AddMinutes(-30)
# $taskTriggerTime = $taskTriggerTime.ToString("HH:mm")

# SPECIFY THESE VARIABLES
$pathToScript = "C:\FULL\PATH\TO\SCRIPT.ps1"
$newTaskName = "MITKY - Schedule Windows Server Backup"
$taskTriggerTime = "HH:mm"
$taskTrigger = New-ScheduledTaskTrigger -At $taskTriggerTime -Daily # Other trigger types can be used

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

