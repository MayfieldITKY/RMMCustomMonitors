# ========================== DATTO COMPONENT MONITOR: =========================
# ================= CHECK WINDOWS SERVER BACKUP SUCCESS EVENT =================
# Checks for success event for Windows Server Backup (Backup log, event ID 4).
# Sends alert if the event is not found, but skips the alert for servers that
# don't run backups over the weekend.

# DEFINE VARIABLES
$successFound = $false
$skipWeekends = $false
$isWeekend = $false

# Check for successful backup event in previous 28 hours (allows for some 
# variation in backup times)
$successEvent = Get-WinEvent -LogName "Microsoft-Windows-Backup" | 
Where-Object {($_.Id -like "4") -and ($_.TimeCreated -gt ((Get-Date).AddHours(-28)))}
if ($successEvent) {$successFound = $true}

# Check if this host should run backups on the weekends. If no variables are set,
# assume weekend backups SHOULD run.
if ([System.Environment]::GetEnvironmentVariable("weekend_backup", "Machine")) {
    $sysVar = [System.Environment]::GetEnvironmentVariable("weekend_backup", "Machine")
    if ($sysVar -ne "TRUE") {$skipWeekends = $true}
} elseif ($env:WeekendBackup) {if ($env:WeekendBackup -eq "FALSE") {$skipWeekends = $true}}
else {$skipWeekends = $false}

# Is it the weekend? Check for Friday's backup on Saturday, no need to check
# backups on Monday.
$isWeekend = $false
if ((Get-Date).DayOfWeek -in ("Sunday", "Monday")) {$isWeekend = $true}

# REPORT AND ALERT IF NECESSARY
if ($successFound) {
    Write-Host '<-Start Result->'
    Write-Host "ALERT=OK: The most recent Windows Server Backup ran successfully."
    Write-Host '<-End Result->'
exit 0 
} elseif ($skipWeekends -and $isWeekend) {
    Write-Host '<-Start Result->'
    Write-Host "ALERT=OK: No weekend backups for this server."
    Write-Host '<-End Result->'
exit 0 
} else {
    Write-Host '<-Start Result->'
    Write-Host "ALERT=Windows Server Backup: no recent success reported!"
    Write-Host '<-End Result->'
exit 1
}
