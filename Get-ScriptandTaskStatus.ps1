
$newTaskName = "MITKY - Check Hyper-V Checkpoints"


Get-ScheduledTask $newTaskName


$scriptFolderPath = "C:\Scripts\RMMCustomMonitors"
$checkpointScriptPath = "$scriptFolderPath\HostServerScripts\HOST-CheckHyperVCheckpoints.ps1"

Test-Path $checkpointScriptPath

