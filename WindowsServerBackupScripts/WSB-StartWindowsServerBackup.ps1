# ================= SCHEDULED TASK: START WINDOWS SERVER BACKUP ===============
# Start a Windows Server Backup job. 

$policy = New-WBPolicy
$VMs = Get-WBVirtualMachine # | Where-Object {$_.VMName -notlike "*test*"}
$lastBackupTarget = $(Get-WBSummary | Select-Object -Property LastBackupTarget).LastBackupTarget
if (-not ($lastBackupTarget)) {
    $lastBackupTarget = Get-PSDrive | Where-Object {($_.Provider -like "*FileSystem") -and (($_.Description -like "*Backup*") -or ($_.Description -like "*WSB*"))}
    if (-not ($lastBackupTarget)) {exit 1}
}

$backupLocation = New-WBBackupTarget -VolumePath $lastBackupTarget.Root

Add-WBBackupTarget -Policy $policy -Target $backupLocation
Add-WBVirtualMachine -Policy $policy -VirtualMachine $VMs

Start-WBBackup -Policy $policy