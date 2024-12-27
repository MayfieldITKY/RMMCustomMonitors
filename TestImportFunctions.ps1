#Import-Module "C:\Scripts\Functions-All.ps1"
#
#Doing-Things
#DontDo-Things
#Break-Things "C:\Scripts\Ooops.txt"

# $eventDetails = ""  Import-Csv .\TestDescriptions.csv
Import-Module ".\ServerMonitorFunctions\ServerMonitorFunctions.ps1"

New-TaskLogFile -taskLogName "ImportEventsTest"

Write-LogAndOutput "I hope I made a log file!"

Write-ReportEvents -eventTaskName "WSB-BackuptheBackups" -eventTaskStatus "deleteRevisionFailed"

$reportParams = @{
    eventTaskName = "Custom Task"
    eventTaskStatus = "Didn't work?"
    eventTaskEventID = 9987
    eventTaskSource = "RMM"
    eventTaskDescription = "I didn't update the reference!"
}

Write-ReportEvents @reportParams

$bigMessage = @"
Here is a big message. I thought it was a good idea to test putting a bunch of
crap in the description to see if we can write a full report to the event log
so here is a big fat string that will go in a big fat array of other big fat
strings and maybe they'll all get in the event log and not look like a big fat
mess? Also, I didn't update the reference, but in this case I think it's probably
fine.
"@
$logThisEvent = "$(Get-EventParameters -eventTaskName "WSB-BackuptheBackups" -eventTaskStatus "deleteRevisionFailed" | Format-List)"
$putTheLogInTheCoconut = "$(Get-Content -Path $taskLogFullName)"
$bigMessageEnd = "Did that work? I hope so? Here's the Downloads folder and it's size I guess:"
$folderName = "C:\Users\jfarris\Downloads"
$folderSize = Get-SpaceUsed $folderName
$folderMessage = "$($folderName) is $($folderSize) GB. Maybe you should clean it out."

$fullMessage = @(
    $bigMessage, " ",
    "$($logThisEvent)", " ",
    "Here's the log so far:",
    $putTheLogInTheCoconut, " ",
    $bigMessageEnd, $folderMessage, " ",
    "OK for real are we done now?"
)


$reportParams = @{
    eventTaskName = "There is no task"
    eventTaskStatus = "Didn't work?"
    eventTaskEventID = 9966
    eventTaskSource = "RMM"
    eventTaskDescription = $fullMessage
}

Write-ReportEvents @reportParams