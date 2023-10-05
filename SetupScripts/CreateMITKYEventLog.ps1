# Creates custom event log named 'MITKY' and adds sources

if (Get-WinEvent -LogName MITKY) {
    Write-Output "Event Log for MITKY already exists."
} else {
    New-EventLog -LogName MITKY -Source 'Scheduled Tasks', 'RMM'
}
