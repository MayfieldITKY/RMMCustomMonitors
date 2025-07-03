# ================= SCHEDULED TASK: START WINDOWS SERVER BACKUP ===============
# Starts a Windows Server Backup job. 
# Check that there is space on the drive for a backup

# Find backup drive
$lastBackupTarget = $(Get-WBSummary | Select-Object -Property LastBackupTarget).LastBackupTarget
$backupTarget = $lastBackupTarget

if (-not ($lastBackupTarget)) {
    $backupTarget = Get-PSDrive | Where-Object {($_.Provider -like "*FileSystem") -and (($_.Description -like "*Backup*") -or ($_.Description -like "*WSB*"))}
    if (-not ($backupTarget)) {exit 1}
}

function Get-FreeSpace {
    [int]$free = 0
    [int]$free = (Get-PSDrive -Name $backupTarget.Replace(":","")).Free / 1GB
    return $free
}

function Get-TotalSizeofVHDs {
    $skipVMsNamed = "Host Component", "*test*", "*no*back*up*", "*(dbu)*"
    $backupVMs = Get-WBVirtualMachine | Where-Object {$_.VMName -notlike $skipVMsNamed}
    $backupVHDs = @()
    foreach ($vm in $backupVMs) {
        $vm = Get-VM -Name $vm.VMName
        $disks = $vm.HardDrives | Where-Object {$_.Path -like "*.vhd*"}
        foreach ($d in $disks) {$backupVHDs += $d.Path}
    }
    $vhdSizes = foreach ($disk in $backupVHDs) {$(Get-ChildItem $disk).Length}
    [int]$vhdSizesTotal = (($vhdSizes | Measure-Object -Sum).Sum) / 1GB

    return $vhdSizesTotal
}

if ((Get-FreeSpace) -lt ((Get-TotalSizeofVHDs) * 1.10)) {
    $btbTaskName = "MITKY*Backup*the*Backups"
    $backupTheBackupsTask = Get-ScheduledTask -TaskName $btbTaskName 
    if ($lastBackupTarget -and $backupTheBackupsTask) {
        $backupTheBackupsTask | Start-ScheduledTask
        while ((Get-ScheduledTask -TaskName $btbTaskName).State -eq "Running") {Start-Sleep 1}
    } else {exit 1}
    if ((Get-FreeSpace) -lt ((Get-TotalSizeofVHDs) * 1.10)) {exit 1}
}


$Script:backupLocation = New-WBBackupTarget -VolumePath $lastBackupTarget.Root
{$Script:backupLocation = New-WBBackupTarget -VolumePath $lastBackupTarget}

# Determine job parameters
$policy = New-WBPolicy
$VMs = Get-WBVirtualMachine # | Where-Object {$_.VMName -notlike "*test*"}
$lastBackupTarget = $(Get-WBSummary | Select-Object -Property LastBackupTarget).LastBackupTarget
if (-not ($lastBackupTarget)) {
    $lastBackupTarget = Get-PSDrive | Where-Object {($_.Provider -like "*FileSystem") -and (($_.Description -like "*Backup*") -or ($_.Description -like "*WSB*"))}
    if (-not ($lastBackupTarget)) {exit 1}
    $Script:backupLocation = New-WBBackupTarget -VolumePath $lastBackupTarget.Root
} else {$Script:backupLocation = New-WBBackupTarget -VolumePath $lastBackupTarget}

Add-WBBackupTarget -Policy $policy -Target $backupLocation
Add-WBVirtualMachine -Policy $policy -VirtualMachine $VMs

Start-WBBackup -Policy $policy








# TESTING

if ((Get-FreeSpace) -lt ((Get-TotalSizeofVHDs) * 1.10)) {
    $taskName = "MITKY*Backup*the*Backups"
    $backupTheBackupsTask = Get-ScheduledTask -TaskName $taskName
    if ($lastBackupTarget -and $backupTheBackupsTask) {
        $backupTheBackupsTask | Start-ScheduledTask
        while ((Get-ScheduledTask -TaskName $taskName).State -eq "Running") {Start-Sleep 1}
    }
}



if ($lastBackupTarget -and (Get-ScheduledTask -TaskName "MITKY*Backup*the*Backups")) {
    Write-Output "Both!"
}




function Get-LastBackupSuccess {
    Write-Output "Checking if last backup was successful..."
    try {Get-WBSummary}
    catch {
        Write-Output 'noWindowsBackup'
        return $false
    }
    $LastWSBDate = (Get-WBSummary).LastBackupTime
    $LastDay = (Get-Date).AddHours(-24)
    $checkDate = $LastWSBDate
    if ($LastDay -lt $LastWSBDate) {$checkDate = $LastDay}
    $LastWSBSuccessEvent = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Backup'; StartTime=$checkDate; Id='4'}
    
    if (-Not($LastWSBSuccessEvent)) {
        Write-Output 'noBackupSuccess'
        return $true
    }      
}




function Get-RevisionNewName($rev) {
    $revContent = Get-ChildItem $rev.FullName | Sort-Object LastWriteTime
    $revDate = Get-Date ($revContent[-1]).LastWriteTime -Format "yyyyMMdd-HHmm"    
    $revNewName = "$($client)_$($hostname)_WindowsImageBackup_$($revDate)"
    return $revNewName
}



$sortFiles = Get-ChildItem "C:\Scripts\Logs" | Sort-Object LastWriteTime

$sortDate = Get-Date ($sortFiles[-1]).LastWriteTime -Format "yyyyMMdd-HHmm"    

