$mainScript = Join-Path $PSScriptRoot 'main.ps1'
Start-Process powershell -ArgumentList "-NoExit", "-File", $mainScript 