using module ..\core\Logger.psm1

function Show-Menu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [string]$Title,
        [string[]]$Options,
        [bool]$ShowBanner = $true,
        [bool]$AllowBack = $false
    )
    $logger = Get-Logger
    $menuOptions = @($Options)
    # Do NOT add 'Go Back' to $menuOptions; only use [b] for back
    $isMainMenu = -not $AllowBack
    while ($true) {
        if ($ShowBanner) {
            $logoPath = $null
            if ($Config -and $Config.ascii_art_path) {
                $logoPath = Join-Path $PSScriptRoot "..\$($Config.ascii_art_path)"
            }
            $asciiArtShown = $false
            if (Get-Module -ListAvailable -Name psAsciiArt) {
                if ($logoPath -and (Test-Path $logoPath)) {
                    try {
                        Import-Module psAsciiArt -ErrorAction Stop
                        ConvertTo-AsciiArt $logoPath -Width 90
                        $asciiArtShown = $true
                    } catch {
                        Write-Host "[DIAG] Error displaying ASCII art: $_" -ForegroundColor Red
                    }
                } elseif ($logoPath) {
                    Write-Host "[DIAG] ASCII art image not found at: $logoPath" -ForegroundColor Yellow
                }
            } else {
                Write-Host "[DIAG] psAsciiArt module not available." -ForegroundColor Yellow
            }
            if (-not $asciiArtShown) {
                Write-Host 'Salesforce Hyperion' -ForegroundColor Yellow
            }
            
            # Show debug status under banner
            $debugStatus = if ($Config.debug) { "ENABLED" } else { "DISABLED" }
            $debugColor = if ($Config.debug) { "Red" } else { "Green" }
            Write-Host "Debug Mode: $debugStatus" -ForegroundColor $debugColor
            Write-Host ""
        }
        Write-Host ("`n$Title") -ForegroundColor Cyan
        Write-BlankLine
        for ($i = 0; $i -lt $menuOptions.Length; $i++) {
            Write-Host ("    [$($i+1)] $($menuOptions[$i])")
        }
        if (-not $isMainMenu) {
            Write-Host "    [b] Go Back" -ForegroundColor Gray
        }
        if ($isMainMenu) {
            Write-Host "    [d] Toggle Debug Mode" -ForegroundColor Gray
        }
        Write-Host "    [x] Exit" -ForegroundColor Gray
        Write-Host ""
        
        $choice = Read-Host 'Enter choice number or special key'
        $logger.LogUserInput($choice, "Menu Choice")
        
        # Handle special keys first
        $choice = $choice.ToLower().Trim()
        if ($choice -eq 'x') {
            Clear-Host
            $logger.LogMenuSelection("Exit", $Title)
            return '__EXIT__'
        }
        if ($choice -eq 'd' -and $isMainMenu) {
            Clear-Host
            $logger.LogMenuSelection("Toggle Debug", $Title)
            return '__TOGGLE_DEBUG__'
        }
        if ($choice -eq 'b' -and $AllowBack -and -not $isMainMenu) {
            Clear-Host
            $logger.LogMenuSelection("Go Back", $Title)
            return '__BACK__'
        }
        
        # Handle empty input
        if ([string]::IsNullOrWhiteSpace($choice)) {
            Clear-Host
            Write-Activity "No option selected. Please enter a valid choice number or special key." -type 'warning'
            $logger.LogWarning("User entered empty choice", "Menu Input")
            Start-Sleep -Seconds 2
            continue
        }
        
        $selectedOption = if ($choice -as [int] -and $choice -ge 1 -and $choice -le $menuOptions.Length) { $menuOptions[$choice-1] } else { $null }
        if ($selectedOption) {
            $confirm = Read-Host "You selected '$selectedOption'. Confirm? (y/n)"
            $logger.LogUserInput($confirm, "Menu Confirmation")
            
            if ($confirm -eq 'y') {
                $logger.LogMenuSelection($selectedOption, $Title)
                return $selectedOption
            } else {
                Clear-Host
                Write-Activity "Selection not confirmed. Please choose again." -type 'warning'
                $logger.LogWarning("Menu selection not confirmed by user")
                # Loop will reload the menu
            }
        } else {
            # Handle invalid input
            Clear-Host
            Write-Activity "Invalid choice '$choice'. Please enter a number between 1 and $($menuOptions.Length) or a special key (b/d/x)." -type 'warning'
            $logger.LogWarning("User entered invalid choice: $choice", "Menu Input")
            Start-Sleep -Seconds 2
            continue
        }
    }
}

function Write-Activity {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string]$Message,
        [string]$type = 'info'
    )
    process {
        $logger = Get-Logger
        
        if ($type -eq 'info') {
            Write-Host (" ~ $Message") -ForegroundColor Green
            $logger.LogInfo($Message, "Activity")
        } elseif ($type -eq 'error') {
            Write-Host (" ! $Message") -ForegroundColor Red
            $logger.LogError($Message, "Activity")
        } elseif ($type -eq 'warning') {
            Write-Host (" x $Message") -ForegroundColor Yellow
            $logger.LogWarning($Message, "Activity")
        } else {
            Write-Host (" ~ $Message") -ForegroundColor Green
            $logger.LogInfo($Message, "Activity")
        }
    }
}

function Write-Table {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Data,
        [Parameter(Mandatory)]
        [string[]]$Columns,
        [string[]]$Headers,
        [string[]]$Alignments = @()
    )
    $logger = Get-Logger
    $logger.LogInfo("Displaying table with $($Data.Count) rows and $($Columns.Count) columns", "Table Display")
    
    if (-not $Headers) { $Headers = $Columns }
    $colWidths = @()
    for ($i = 0; $i -lt $Columns.Length; $i++) {
        $col = $Columns[$i]
        $maxLen = (
            $Data | ForEach-Object {
                $val = $_.$col
                if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                    ($val | ForEach-Object { ($_ | Out-String).Trim().Length } | Measure-Object -Maximum).Maximum
                } else {
                    ($val | Out-String).Trim().Length
                }
            } | Measure-Object -Maximum
        ).Maximum
        $headerLen = $Headers[$i].Length
        $colWidths += [Math]::Max($maxLen, $headerLen)
    }
    # Print header
    $headerLine = ""
    for ($i = 0; $i -lt $Headers.Length; $i++) {
        $headerLine += $Headers[$i].PadRight($colWidths[$i])
        if ($i -lt $Headers.Length - 1) { $headerLine += " | " }
    }
    Write-Host $headerLine -ForegroundColor Magenta
    # Print separator
    $sepLine = ""
    for ($i = 0; $i -lt $colWidths.Count; $i++) {
        $sepLine += ('-' * $colWidths[$i])
        if ($i -lt $colWidths.Count - 1) { $sepLine += "-+-" }
    }
    Write-Host $sepLine -ForegroundColor Magenta
    # Print rows with multi-line support
    foreach ($row in $Data) {
        $rowValues = @()
        $maxLines = 1
        for ($i = 0; $i -lt $Columns.Length; $i++) {
            $val = $row.$($Columns[$i])
            if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                $lines = @($val | ForEach-Object { ($_ | Out-String).Trim() })
                $rowValues += ,$lines
                if ($lines.Count -gt $maxLines) { $maxLines = $lines.Count }
            } else {
                $rowValues += ,@(($val | Out-String).Trim())
            }
        }
        for ($lineIdx = 0; $lineIdx -lt $maxLines; $lineIdx++) {
            $lineStr = ""
            for ($i = 0; $i -lt $rowValues.Count; $i++) {
                $cellLines = $rowValues[$i]
                $cellVal = if ($lineIdx -lt $cellLines.Count) { $cellLines[$lineIdx] } else { "" }
                $lineStr += $cellVal.PadRight($colWidths[$i])
                if ($i -lt $rowValues.Count - 1) { $lineStr += " | " }
            }
            Write-Host $lineStr
        }
        Write-Host $sepLine -ForegroundColor Magenta
    }
}

function Write-BlankLine {
    Write-Host ""
}

function Read-VerifiedPassword {
    [CmdletBinding()]
    param(
        [string]$Prompt = "Enter password"
    )
    $logger = Get-Logger
    $logger.LogInfo("Password verification prompt started", "Password Input")
    
    while ($true) {
        Write-BlankLine
        $pw1 = Read-Host "$Prompt" -AsSecureString
        $logger.LogUserInput("[PASSWORD ENTERED]", "First Password Entry")
        
        $pw2 = Read-Host "Re-enter password to confirm" -AsSecureString
        $logger.LogUserInput("[PASSWORD ENTERED]", "Second Password Entry")
        
        if (([System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw1))) -eq ([System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw2)))) {
            Write-Activity "Password entries match." -type 'info'
            Write-BlankLine
            $logger.LogInfo("Password verification successful", "Password Input")
            return $pw1
        } else {
            Write-Activity "Passwords do not match. Please try again." -type 'error'
            Write-BlankLine
            $logger.LogWarning("Password verification failed - passwords do not match", "Password Input")
        }
    }
}

function Initialize-ProgressBar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$TotalTasks,
        [string]$Description = "Processing tasks"
    )
    $logger = Get-Logger
    $logger.LogInfo("Initializing progress bar for $TotalTasks tasks: $Description", "Progress Bar")
    
    $progressBar = [PSCustomObject]@{
        TotalTasks = $TotalTasks
        CompletedTasks = 0
        Description = $Description
        StartTime = Get-Date
        Activity = $Description
        Id = [System.Guid]::NewGuid().ToString()
    }
    
    # Initial progress
    Write-Progress -Id 1 -Activity $progressBar.Description -Status "Starting..." -PercentComplete 0
    return $progressBar
}

function Update-ProgressBar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ProgressBar,
        [int]$CompletedTasks = 1,
        [string]$CurrentTask = ""
    )
    $ProgressBar.CompletedTasks += $CompletedTasks
    $percent = [Math]::Min(100, [Math]::Round(($ProgressBar.CompletedTasks / $ProgressBar.TotalTasks) * 100))
    $status = if ($CurrentTask) { $CurrentTask } else { "$($ProgressBar.CompletedTasks)/$($ProgressBar.TotalTasks)" }
    Write-Progress -Id 1 -Activity $ProgressBar.Description -Status $status -PercentComplete $percent
    if ($percent % 10 -eq 0 -or $ProgressBar.CompletedTasks -eq $ProgressBar.TotalTasks) {
        $logger = Get-Logger
        $logger.LogInfo("Progress: $($ProgressBar.CompletedTasks)/$($ProgressBar.TotalTasks) tasks completed ($percent%)", "Progress Bar")
    }
}

function Complete-ProgressBar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ProgressBar
    )
    $logger = Get-Logger
    $duration = (Get-Date) - $ProgressBar.StartTime
    $logger.LogInfo("Progress bar completed. Total time: $($duration.ToString('mm\:ss'))", "Progress Bar")
    Write-Progress -Id 1 -Activity $ProgressBar.Description -Status "Completed" -PercentComplete 100 -Completed
    Write-Host ""
}

Export-ModuleMember -Function Show-Menu, Write-Activity, Print-Activity, Write-Table, Write-BlankLine, Read-VerifiedPassword, Initialize-ProgressBar, Update-ProgressBar, Complete-ProgressBar