# Check for Shadow Copies on Server Hosts
# Checks for existing shadow copies and outputs if they are present

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