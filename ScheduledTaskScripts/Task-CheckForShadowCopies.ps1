# Checks for shadow copies on host server.
# Runs as a scheduled task and writes status to MITKY Event Log.
# RMM monitors this log and alerts if shadow copies are found.

if (Get-WmiObject Win32_ShadowCopy) {
  $params = @{
    LogName = "MITKY"
    Source = "Scheduled Tasks"
    EntryType = "Warning"
    EventId = 1061
    Message = "Shadow copies found on host server."
  }
  Write-EventLog @params
} else {
  $params = @{
    LogName = "MITKY"
    Source = "Scheduled Tasks"
    EntryType = "Information"
    EventId = 1069
    Message = "No shadow copies found on host server."
  }
  Write-EventLog @params
}