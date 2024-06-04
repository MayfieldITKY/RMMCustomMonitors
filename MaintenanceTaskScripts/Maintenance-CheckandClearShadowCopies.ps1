
# ============== MAINTENANCE TASK: CHECK AND CLEAR SHADOW COPIES ==============
<#
Checks for shadow copies on a HOST server and attempts to delete them by
resizing shadow copy storage. The script will find all volumes with shadow copies
and continue trying to clear them unless the disk space used by shadow copies is
not decreasing after an attempt. It will write results to the MITKY event log,
and RMM will monitor and alert only if shadow copies exist and could not be cleared.
#>
# =============================================================================

# Define all needed functions
Function Get-VolumesWithShadows () {
    $volumes = @()
    $allShadowCopies = Get-CimInstance -Class "Win32_ShadowCopy"
    foreach ($copy in $allShadowCopies) {
        if (-not ($volumes -contains $copy.VolumeName)) {$volumes += $copy.VolumeName}
    }
    $volumes
}

Function Get-DriveLetter ($volume) {
    $v = Get-CimInstance win32_volume | Where-Object {$_.DeviceID -eq $volume}
    $v.Name
}

Function Get-ShadowSpace ($volume) {
    $spaceUsed = Get-CimInstance -Class Win32_ShadowStorage | Where-Object {$_.Volume.DeviceID -eq $volume} | Select-Object UsedSpace
    $spaceUsed
}

Function Get-VolumesToClear ($volume) {
    $usedSpace = Get-ShadowSpace $volume | Select-Object -ExpandProperty UsedSpace
    $volumeData = @{ID = $volume; Letter = (Get-DriveLetter $volume); UsedSpace = $usedSpace}
    $volumeData
}

Function Remove-ShadowCopies ($drive) {
    $commandRemove = "vssadmin resize shadowstorage /for=$drive /on=$drive /maxsize=320MB"
    $commandUnbound = "vssadmin resize shadowstorage /for=$drive /on=$drive /maxsize=unbounded"
    cmd.exe /c $commandRemove
    cmd.exe /c $commandUnbound
}

# =============================================================================

# Check if shadow copies exist. If any, get volumes with shadows and relevant data
if (-not (Get-CimInstance -Class "Win32_ShadowCopy" -ErrorAction Ignore)) {
    # No shadow copies, so write to event log and exit
    $params = @{
        LogName = "MITKY"
        Source = "Scheduled Tasks"
        EntryType = "Information"
        EventId = 1069
        Message = "No shadow copies were found on host server."
    }
    Write-EventLog @params
    exit
}

$volumesToClear = @()
foreach ($vol in Get-VolumesWithShadows) {$volumesToClear += Get-VolumesToClear $vol}

# For each volume, get drive letter and attempt to clear shadow copies
$allShadowsCleared = $false

foreach ($vol in $volumesToClear) {
    $letter = $vol.Letter
    $usedSpaceBefore = $vol.UsedSpace

    # Initial clear attempt
    Remove-ShadowCopies $letter
    $usedSpaceAfter = Get-ShadowSpace $vol | Select-Object -ExpandProperty UsedSpace

    # Additional attempts if needed. Stop if used space does not reduce after an attempt
    if ($usedSpaceAfter -ne 0) {
        While ($usedSpaceBefore -gt $usedSpaceAfter) {
            $usedSpaceBefore = $usedSpaceAfter
            Remove-ShadowCopies $letter
            $usedSpaceAfter = Get-ShadowSpace $vol | Select-Object -ExpandProperty UsedSpace
            if ($usedSpaceAfter -eq 0) {
                break
            }
        }
    }
}

# Check that all shadows were cleared for all volumes and report results to event log
if (-not (Get-CimInstance -Class "Win32_ShadowCopy")) {$allShadowsCleared = $true}

if ($allShadowsCleared) {
    $params = @{
        LogName = "MITKY"
        Source = "Scheduled Tasks"
        EntryType = "Information"
        EventId = 1068
        Message = "Shadow copies were found on host server and successfully cleared."
    }
    Write-EventLog @params
} else {
    $params = @{
        LogName = "MITKY"
        Source = "Scheduled Tasks"
        EntryType = "Information"
        EventId = 1061
        Message = "Shadow copies were found on host server and could not be cleared!"
    }
    Write-EventLog @params
}
    