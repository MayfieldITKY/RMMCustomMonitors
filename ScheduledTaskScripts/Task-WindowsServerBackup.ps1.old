# Windows Server Backup Monitor
# Check for backup success event (Event ID 4) within last 28 hours and output Success or Failure
# Use 28 hours to allow for variance in backup duration

$Date = (Get-Date).AddHours(-28)
$SuccessEvent = Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-Backup'; StartTime=$Date; Id='4' }
if ( $SuccessEvent )
{
    $Success = 'Windows Server Backup completed successfully'
} else {
    $Success = 'Windows Server Backup failed to complete'
}
Write-Output $Success