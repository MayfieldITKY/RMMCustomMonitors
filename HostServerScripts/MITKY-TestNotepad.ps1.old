# Creates a text file and opens it in Notepad
$testFile = "TestNotepadFile.txt"
$testFilePath = "C:\scripts\$testFile"

if (-not (Test-Path $testFilePath)) {
    New-Item -Path $testFilePath -Force
}

$runTime = Get-Date
$appendText = "The task last updated at: $runTime"
Add-Content -Path $testFilePath -Value $appendText
Start-Process notepad $testFilePath
