# ============== CREATE ENVIRONMENT VARIABLES: TASK SCHEDULING ================
# Creates or updates system variables to control scheduled task triggers based
# on Windows Server Backup schedule. First determine when backups will start,
# then base the times for other tasks on the backup time. 

# SET VARIABLES
# These can be modified safely
$defaultStartTime = "20:00"
$newStartTimeVarName = "backup_start_time"
$newBackupBackupsTimeVarName = "backup_the_backups_time"
$newClearShadowCopiesTimeVarName = "clear_shadow_copies_time"
$newGetVMCheckpointsTimeVarName = "get_checkpoints_time"

# Do not modify these variables
$hostname = $env:COMPUTERNAME
$site = $env:short_site_name
$oldStartTimeVarName = "backup_start_time"
$oldBackupBackupsTimeVarName = "backup_the_backups_time"
$oldClearShadowCopiesTimeVarName = "clear_shadow_copies_time"
$oldGetVMCheckpointsTimeVarName = "get_checkpoints_time"

$allSysVarNames = @{
    backupStartTime = $newStartTimeVarName, $oldStartTimeVarName
    backupBackupsTime = $newBackupBackupsTimeVarName, $oldBackupBackupsTimeVarName
    clearShadowsTime = $newClearShadowCopiesTimeVarName, $oldClearShadowCopiesTimeVarName
    getCheckpointsTime = $newGetVMCheckpointsTimeVarName, $oldGetVMCheckpointsTimeVarName
}

# DEFINE FUNCTIONS
function Get-CurrentTask([string]$taskName) {
    if ($taskName -notlike "MITKY*") {return $false}
    Get-ScheduledTask -TaskName $taskName -ErrorAction Ignore
}

function Get-CurrentTaskStartTime([string]$taskName) {
    $triggerStart = Get-ScheduledTask -TaskName $taskName | 
        Select-Object -ExpandProperty Triggers | 
        Select-Object -ExpandProperty StartBoundary
    if ($triggerStart.count -ne 1) {return $false}
    return Get-Date $triggerStart -Format "HH:mm"
}

function Get-SystemVariable([string]$eVarName) {[System.Environment]::GetEnvironmentVariable($eVarName, "Machine")}

function Set-CustomSystemVariable([string]$eVarName, [string]$eVarValue) {
    If (-Not (([System.Environment]::GetEnvironmentVariable($eVarName, "Machine")) -eq $eVarValue)) {
        [System.Environment]::SetEnvironmentVariable($eVarName,$eVarValue,[System.EnvironmentVariableTarget]::Machine)
    }
}

function Remove-OldSystemVariable([string]$oldVarName, [string]$newVarName) {
    if ($oldVarName -eq $newVarName) {return}
    elseif ([System.Environment]::GetEnvironmentVariable($oldVarName, "Machine")) {
        $value = [System.Environment]::GetEnvironmentVariable($oldVarName, "Machine")
        Set-CustomSystemVariable $newVarName $value
        [System.Environment]::SetEnvironmentVariable($oldVarName, "", "Machine")
    } else {return}
}

# CLEAN UP SYSTEM VARIABLES
# In case variables have been renamed, remove any old variables
foreach ($var in $allSysVarNames.Keys) {
    $names = $allSysVarNames.$var
    if (Get-SystemVariable $names[1]) {
        if ($names[0] -ne $names[1]) {Remove-OldSystemVariable $names[1] $names[0]}
    }
}

# DETERMINE WINDOWS SERVER BACKUP START TIME
# If there are no VMs or backup set up, don't do anything
if (-Not ((Get-VM) -or (Get-WBSummary -ErrorAction Ignore) -or (Get-WBPolicy -ErrorAction Ignore))) {exit 1}

# Set the backup start time, preferring the current task time, then the current
# variable value, then the schedule set by WSB, and finally using the default
# time if needed.
$newBackupTaskName = "MITKY - Start Windows Server Backup"
$backupTaskName = "MITKY - Schedule Windows Server Backup"

$backupStartTime = $defaultStartTime
if (Get-CurrentTaskStartTime $newBackupTaskName) {
    $backupStartTime = Get-CurrentTaskStartTime $newBackupTaskName
} elseif (Get-CurrentTaskStartTime $backupTaskName) {
    $backupStartTime = Get-CurrentTaskStartTime $backupTaskName
} elseif ([System.Environment]::GetEnvironmentVariable($newStartTimeVarName, "Machine")) {
    $backupStartTime = $env:backup_start_time
} elseif ((Get-WBPolicy -ErrorAction Ignore) -and ((Get-WBSummary).NextBackupTime)) {
    $backupStartTime = Get-Date $((Get-WBSummary).NextBackupTime) -Format "HH:mm"
} else {}

if (-Not (Get-Date $backupStartTime -ErrorAction Ignore)) {$backupStartTime = $defaultStartTime}
Set-CustomSystemVariable $newStartTimeVarName $backupStartTime

# SET OTHER VARIABLES BASED ON BACKUP START TIME
$backupBackupsTime = $(Get-Date $((Get-Date $backupStartTime).AddMinutes(-20)) -Format "HH:mm")
Set-CustomSystemVariable $newBackupBackupsTimeVarName $backupBackupsTime

$clearShadowsTime = $(Get-Date $((Get-Date $backupStartTime).AddMinutes(-40)) -Format "HH:mm")
Set-CustomSystemVariable $newClearShadowCopiesTimeVarName $clearShadowsTime

$getCheckpointsTime = $(Get-Date $((Get-Date $backupStartTime).AddMinutes(-60)) -Format "HH:mm")
Set-CustomSystemVariable $newGetVMCheckpointsTimeVarName $getCheckpointsTime
