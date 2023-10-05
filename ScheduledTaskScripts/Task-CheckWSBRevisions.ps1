# Checks for Windows Server Backup revisions on host server.
# Runs as a scheduled task and writes status to MITKY Event Log.
# RMM monitors this log and alerts if not enough revisions are found.

# Get information about Windows Server Backup schedule and contents of backup drive.
Write-Host "Checking Windows Server Backup..."
$winBupDriveLetter = (Get-WBSummary).LastBackupTarget
$winBupDrive = Get-WmiObject -Class Win32_logicaldisk -Filter "DeviceID = '$winBupDriveLetter'"
$winBupDriveContents = $winBupDriveLetter | Get-ChildItem
$revisions = (Get-WBSummary).LastBackupTarget | Get-ChildItem | Where-Object {$_.Name -like "*WindowsImageBackup*"}

# If there are no recent errors, get data about revisions and drive space
Write-Host "Checking internal backup drive..."
$winBupRecentFailure = $false
$winBupErrors = Get-WBJob -previous 4 | Where-Object {$_.HResult -ne "0"}
if ($winBupErrors.length -gt 0) {$winBupRecentFailure = $true}
[array] $revisionSizes = foreach ($rev in $revisions) {Get-ChildItem $winBupDriveLetter\$rev -Recurse | Measure-Object -property length -sum}
$revisionTypicalSize = ($revisionSizes.Sum | Measure-Object -Average)
$revisionTypicalSizeGB = "{0:N2} GB" -f (($revisionSizes.Sum | Measure-Object -Average).Average / 1GB)
$winBupDriveFreeSpace = "{0:N2} GB" -f ($winBupDrive.FreeSpace / 1GB)
$enoughRevisions = $false
if ($revisions.Length -gt 3) {$enoughRevisions = $true}
$spaceforNewRevision = $false
if ($winBupDrive.FreeSpace -gt ($revisionTypicalSize.Average) * 1.6) {$spaceforNewRevision = $true}
$notenoughSpace = $false
if ($winBupDrive.FreeSpace -lt ($revisionTypicalSize.Average) * 0.1) {$notenoughSpace = $true}
$nonBupData = $false
if ($winBupDriveContents.Length -gt $revisions.Length) {$nonBupData = $true}



$bupDriveAssessment = ""
# FIRST check for at least four revisions
if (($enoughRevisions -eq $false) -and ($spaceforNewRevision -eq $false)) {
    $bupDriveAssessment = "<p id='Text'>There are less than four revisions, but there is not enough space to add a revision. <br>
    This calculation allows for growth of the backup file by up to 20%.</p>"
    }

if (($enoughRevisions -eq $false) -and ($spaceforNewRevision -eq $true)) {
    $bupDriveAssessment = "<p id='Text'>There are less than four revisions, and there is sufficient space to add a revision. <br>
    This calculation allows for growth of the backup file by up to 20%.</p>"
    }

if (($enoughRevisions -eq $true) -and ($notenoughSpace -eq $false)) {
    $bupDriveAssessment = "<p id='GoodText'>There are at least four revisions. No additional revisions are needed.</p>"
    }

# THEN check if the drive is full
if (($notenoughSpace -eq $true) -and ($nonBupData -eq $true)) {
    $bupDriveAssessment = "<p id='Text'>The drive is getting full. There are additional files on the drive, consider deleting them if they are not needed.</p>"
    }

if (($notenoughSpace -eq $true) -and ($nonBupData -eq $false)) {
$bupDriveAssessment = "<p id='Text'>The drive is getting full. It may be necessary to decrease the number of revisions.</p>"
    }

# THEN check for failed backups because they will cause the revision size estimate to be inaccurate
if  ($winBupRecentFailure -eq $true) {
    $bupDriveAssessment = "<p id='ErrorText'>Cannot assess revisions on backup drive due to recent Windows Server Backup failures. Revision size estimate is probably wrong!</p>"
}

