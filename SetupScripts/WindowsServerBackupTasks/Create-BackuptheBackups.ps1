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
This only runs after a successful Windows Server Backup.
"@
# Create a test task with the correct trigger and export it, then find the <Subscription> tag under <Triggers>
$triggerSubscription = @"
<QueryList><Query Id="0" Path="Microsoft-Windows-Backup">
<Select Path="Microsoft-Windows-Backup">*[System[Provider[@Name='Microsoft-Windows-Backup'] and EventID=4]]
</Select></Query></QueryList>
"@
$triggerDelay = "PT30M" # 30 minutes after trigger event

# =============================================================================
# DO NOT CHANGE BELOW THIS LINE
$arguments = "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $pathToScript"
$User = "NT AUTHORITY\SYSTEM"
$Action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument $arguments
$taskPath = "MayfieldIT"

# Task trigger on event ID
$triggerClass = Get-cimclass MSFT_TaskEventTrigger root/Microsoft/Windows/TaskScheduler
$taskTrigger = $triggerClass | New-CimInstance -ClientOnly
$taskTrigger.Enabled = $true
$taskTrigger.Subscription = $triggerSubscription
$taskTrigger.Delay = $triggerDelay

$newTaskParams = @{
  TaskName = $newTaskName
  Description = $newTaskDescription
  TaskPath = $taskPath
  Action = $Action
  User = $User
  RunLevel = "Highest"
  Trigger = $taskTrigger
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
