# Checks for Hyper-V Checkpoints on server hosts. Excludes RDC and TESTING VMs.
# Runs as a scheduled task and writes status to Event Log.
# RMM monitors this log and alerts if checkpoints are found.

$checkpoints = Get-VM * | Where-Object{$_.Name -notlike "*RDC*" -and $_.Name -notlike "*test*"} | ForEach-Object {Get-VMCheckpoint -VMName $_.Name}

if ($checkpoints) {
    $params = @{
        LogName = "MITKY"
        Source = "Scheduled Tasks"
        EntryType = "Warning"
        EventId = 1001
        Message = "Hyper-V checkpoints were detected. Check if they are still needed or can be deleted."
    }
    
    Write-EventLog @params
} else {
    $params = @{
        LogName = "MITKY"
        Source = "Scheduled Tasks"
        EntryType = "Information"
        EventId = 1009
        Message = "No Hyper-V checkpoints were detected. This does not include RDC or testing VMs."
    }
    
    Write-EventLog @params
}
