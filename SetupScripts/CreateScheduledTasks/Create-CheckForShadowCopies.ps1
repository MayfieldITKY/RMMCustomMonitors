# Creates scheduled task to check for shadow copies on server host

$TaskName = "MITKY - Check for Shadow Copies"
$Trigger = New-ScheduledTaskTrigger -At 7:00am -Daily
$User = "NT AUTHORITY\SYSTEM"
$Action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "C:\Scripts\CustomMonitors\ScheduledTaskScripts\CheckForShadowCopies.ps1"

Register-ScheduledTask -TaskName $TaskName -Trigger $Trigger -User $User -Action $Action