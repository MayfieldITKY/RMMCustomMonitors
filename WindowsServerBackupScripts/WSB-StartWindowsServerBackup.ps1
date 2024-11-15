# ================= SCHEDULED TASK: START WINDOWS SERVER BACKUP ===============

# Start a Windows Server Backup job. 

$policy = New-WBPolicy
$VMs = Get-WBVirtualMachine # | Where-Object {$_.VMName -notlike "*test*"}
$backupLocation = New-WBBackupTarget -VolumePath "D:"

Add-WBBackupTarget -Policy $policy -Target $backupLocation
Add-WBVirtualMachine -Policy $policy -VirtualMachine $VMs

Start-WBBackup -Policy $policy