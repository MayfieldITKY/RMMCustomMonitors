# ============================== CREATE EVENT LOG =============================
# Creates custom event log for RMM monitoring and maintenance scripts. This is
# the custom event log that the RMM monitors will check. IF THIS DOESN'T WORK 
# THEN NO RMM MONITORS WILL WORK!
Write-Output "Creating or updating custom event log..."
New-EventLog -LogName MITKY -Source 'Scheduled Tasks', 'Maintenance Tasks', 'RMM' -ErrorAction Ignore
if (Get-EventLog -LogName * | Where-Object {$_.Log -like "MITKY"}) {Write-Output "Event log created successfully!"}
else {
    Write-Output "Could not create event log! Exiting..."
    exit 1
}

# Create custom view
$customViewFilterXml = @"
<ViewerConfig>
    <QueryConfig>
        <QueryParams>
            <Simple>
                <Channel>MITKY</Channel>
                <RelativeTimeInfo>0</RelativeTimeInfo>
                <BySource>False</BySource>
            </Simple>
        </QueryParams>
        <QueryNode>
            <Name>MITKY</Name>
            <Description>Mayfield IT custom events</Description>
            <QueryList>
                <Query Id="0">
                    <Select Path="MITKY">*</Select>
                </Query>
            </QueryList>
        </QueryNode>
    </QueryConfig>
</ViewerConfig>
"@

$customViewFilePath = "C:\ProgramData\Microsoft\Event Viewer\Views\MITKY.xml"
if (Test-Path $customViewFilePath) {Remove-Item -Path $customViewFilePath -Force}
New-Item -Path $customViewFilePath -ItemType "File" -Value $customViewFilterXml -Force

if (Test-Path $customViewFilePath) {Write-Output "Created custom view for MITKY event log."}
else {
    Write-Output "Could not create custom view for MITKY event log! Exiting..."
    exit 1
}
exit 0
