# ============== MONITORING TASK: CHECK FOR HYPER-V CHECKPOINTS ================
# Checks for Hyper-V Checkpoints on server hosts. Excludes RDC and TESTING VMs.
# Runs as a scheduled task and writes status to Event Log.
# RMM monitors this log and alerts if checkpoints are found.

try {Get-VM}
catch {
        $params = @{
            LogName = "MITKY"
            Source = "Scheduled Tasks"
            EntryType = "Warning"
            EventId = 1000
            Message = "No Virtual Machines were detected or the Get-VM cmdlet failed! Check if Hyper-V is enabled for this server or if VMs should be present."
        }
        
        Write-EventLog @params
        exit
}


$checkpoints = Get-VM * | Where-Object{$_.Name -notlike "*test*"} | ForEach-Object {Get-VMCheckpoint -VMName $_.Name}

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
