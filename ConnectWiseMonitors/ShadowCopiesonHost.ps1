# Checks MITKY event log for existing shadow copies on server host

$Date = (Get-Date).AddHours(-24)
$SuccessEvent = Get-WinEvent -FilterHashtable @{ LogName='MITKY'; StartTime=$Date; Id='1069' }
if ( $SuccessEvent )
{
    $Result = 'No shadow copies found on host server.'
} else {
    $Result = 'There are existing shadow copies on the host server.'
}
Write-Output $Result