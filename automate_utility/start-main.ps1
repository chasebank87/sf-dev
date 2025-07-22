# This script launches main.ps1 in a new maximized PowerShell window
$mainScript = Join-Path $PSScriptRoot 'main.ps1'
Start-Process powershell.exe -ArgumentList "-NoExit", "-File `"$mainScript`"" -WindowStyle Maximized 