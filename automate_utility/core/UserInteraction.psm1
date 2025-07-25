using module ..\core\Logger.psm1

class UserInteraction {
    UserInteraction() {}

    [string] ShowMenu([object]$Config, [string]$Title, [string[]]$Options, [bool]$ShowBanner = $true, [bool]$AllowBack = $false) {
        $logger = Get-Logger
        $menuOptions = @($Options)
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
                $debugStatus = if ($Config.debug) { "ENABLED" } else { "DISABLED" }
                $debugColor = if ($Config.debug) { "Red" } else { "Green" }
                Write-Host "Debug Mode: $debugStatus" -ForegroundColor $debugColor
                Write-Host ""
            }
            Write-Host ("`n$Title") -ForegroundColor Cyan
            [UserInteraction]::WriteBlankLine()
            for ($i = 0; $i -lt $menuOptions.Length; $i++) {
                Write-Host ("    [$($i+1)] $($menuOptions[$i])")
            }
            if (-not $isMainMenu) {
                Write-Host "    [b] Go Back" -ForegroundColor Cyan
            }
            if ($isMainMenu) {
                Write-Host "    [d] Toggle Debug Mode" -ForegroundColor Yellow
            }
            Write-Host "    [x] Exit" -ForegroundColor Red
            Write-Host ""
            $choice = Read-Host 'Enter choice number or special key'
            $logger.LogUserInput($choice, "Menu Choice")
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
            if ([string]::IsNullOrWhiteSpace($choice)) {
                Clear-Host
                [UserInteraction]::WriteActivity("No option selected. Please enter a valid choice number or special key.", 'warning')
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
                    [UserInteraction]::WriteActivity("Selection not confirmed. Please choose again.", 'warning')
                    $logger.LogWarning("Menu selection not confirmed by user", "Menu Input")
                }
            } else {
                Clear-Host
                [UserInteraction]::WriteActivity("Invalid choice '$choice'. Please enter a number between 1 and $($menuOptions.Length) or a special key (b/d/x).", 'warning')
                $logger.LogWarning("User entered invalid choice: $choice", "Menu Input")
                Start-Sleep -Seconds 2
                continue
            }
        }
        return '' # Default return to satisfy linter
    }

    static [void] ShowScriptTitle([string]$Title) {
        if (Get-Module -ListAvailable -Name WriteAscii) {
            try {
                Import-Module WriteAscii -ErrorAction Stop
                Write-Ascii $Title -ForegroundColor Black -BackgroundColor Cyan
            } catch {
                Write-Host ("===== $Title =====") -ForegroundColor Cyan
            }
        } else {
            Write-Host ("===== $Title =====") -ForegroundColor Cyan
        }
    }

    static [void] WriteActivity([string]$Message, [string]$type = 'info') {
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

    [void] WriteTable([array]$Data, [string[]]$Columns, [string[]]$Headers, [string[]]$Alignments = @(), [hashtable]$ColorMappings = @{}) {
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
        $headerLine = ""
        for ($i = 0; $i -lt $Headers.Length; $i++) {
            $headerLine += $Headers[$i].PadRight($colWidths[$i])
            if ($i -lt $Headers.Length - 1) { $headerLine += " | " }
        }
        Write-Host $headerLine -ForegroundColor Magenta
        $sepLine = ""
        for ($i = 0; $i -lt $colWidths.Count; $i++) {
            $sepLine += ('-' * $colWidths[$i])
            if ($i -lt $colWidths.Count - 1) { $sepLine += "-+-" }
        }
        Write-Host $sepLine -ForegroundColor Magenta
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
                for ($i = 0; $i -lt $rowValues.Count; $i++) {
                    $cellLines = $rowValues[$i]
                    $cellVal = if ($lineIdx -lt $cellLines.Count) { $cellLines[$lineIdx] } else { "" }
                    $paddedVal = $cellVal.PadRight($colWidths[$i])
                    
                    # Check for custom color mapping for this column and value
                    $columnName = $Columns[$i]
                    $color = "White"  # Default color
                    if ($ColorMappings.ContainsKey($columnName) -and $ColorMappings[$columnName].ContainsKey($cellVal)) {
                        $color = $ColorMappings[$columnName][$cellVal]
                    }
                    
                    Write-Host $paddedVal -ForegroundColor $color -NoNewline
                    if ($i -lt $rowValues.Count - 1) { Write-Host " | " -NoNewline }
                }
                Write-Host ""  # New line after each row
            }
            Write-Host $sepLine -ForegroundColor Magenta
        }
    }

    static [void] WriteBlankLine() {
        Write-Host ""
    }

    static [void] WriteTable([array]$Data, [string[]]$Columns, [object]$Headers = $null, [object]$Alignments = $null, [object]$ColorMappings = $null) {
        if ($null -eq $Headers) { $Headers = $Columns }
        if ($null -eq $Alignments) { $Alignments = @() }
        if ($null -eq $ColorMappings) { $ColorMappings = @{} }
        $ui = [UserInteraction]::new()
        $ui.WriteTable($Data, $Columns, $Headers, $Alignments, $ColorMappings)
    }

    [System.Security.SecureString] ReadVerifiedPassword([string]$Prompt = "Enter password") {
        $logger = Get-Logger
        $logger.LogInfo("Password verification prompt started", "Password Input")
        while ($true) {
            [UserInteraction]::WriteBlankLine()
            $pw1 = Read-Host "$Prompt" -AsSecureString
            $logger.LogUserInput("[PASSWORD ENTERED]", "First Password Entry")
            $pw2 = Read-Host "Re-enter password to confirm" -AsSecureString
            $logger.LogUserInput("[PASSWORD ENTERED]", "Second Password Entry")
            if (([System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw1))) -eq ([System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw2)))) {
                [UserInteraction]::WriteActivity("Password entries match.", 'info')
                [UserInteraction]::WriteBlankLine()
                $logger.LogInfo("Password verification successful", "Password Input")
                return $pw1
            } else {
                [UserInteraction]::WriteActivity("Passwords do not match. Please try again.", 'error')
                [UserInteraction]::WriteBlankLine()
                $logger.LogWarning("Password verification failed - passwords do not match", "Password Input")
            }
        }
        return $null # Default return to satisfy linter
    }

    [object] InitializeProgressBar([int]$TotalTasks, [string]$Description = "Processing tasks") {
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
        Write-Progress -Id 1 -Activity $progressBar.Description -Status "Starting..." -PercentComplete 0
        return $progressBar
    }

    [void] UpdateProgressBar([object]$ProgressBar, [int]$CompletedTasks = 1, [string]$CurrentTask = "") {
        $ProgressBar.CompletedTasks += $CompletedTasks
        $percent = [Math]::Min(100, [Math]::Round(($ProgressBar.CompletedTasks / $ProgressBar.TotalTasks) * 100))
        $status = if ($CurrentTask) { $CurrentTask } else { "$($ProgressBar.CompletedTasks)/$($ProgressBar.TotalTasks)" }
        Write-Progress -Id 1 -Activity $ProgressBar.Description -Status $status -PercentComplete $percent
        if ($percent % 10 -eq 0 -or $ProgressBar.CompletedTasks -eq $ProgressBar.TotalTasks) {
            $logger = Get-Logger
            $logger.LogInfo("Progress: $($ProgressBar.CompletedTasks)/$($ProgressBar.TotalTasks) tasks completed ($percent%)", "Progress Bar")
        }
    }

    [void] CompleteProgressBar([object]$ProgressBar) {
        $logger = Get-Logger
        $duration = (Get-Date) - $ProgressBar.StartTime
        $logger.LogInfo("Progress bar completed. Total time: $($duration.ToString('mm\:ss'))", "Progress Bar")
        Write-Progress -Id 1 -Activity $ProgressBar.Description -Status "Completed" -PercentComplete 100 -Completed
        Write-Host ""
    }

    [string] PromptUserForConfirmation([string]$Message) {
        $response = Read-Host $Message
        if ($null -eq $response) { return '' }
        return $response
    }

    static [string] PromptWithTimeout([string]$Prompt, [int]$TimeoutSeconds = 3) {
        for ($elapsed = 0; $elapsed -lt $TimeoutSeconds; $elapsed++) {
            Write-Host $Prompt -NoNewline
            $start = Get-Date
            while (((Get-Date) - $start).TotalSeconds -lt 1) {
                if ([System.Console]::KeyAvailable) {
                    $key = [System.Console]::ReadKey($true)
                    Write-Host ""  # Move to next line after keypress
                    return $key.KeyChar
                }
                Start-Sleep -Milliseconds 100
            }
        }
        Write-Host ""  # Move to next line after timeout
        return $null
    }

    static [void] WriteInlineProgressBar([int]$Current, [int]$Total, [string]$Label = "Progress", [int]$BarWidth = 20) {
        $logger = Get-Logger
        
        # Calculate percentage
        $percentage = if ($Total -gt 0) { [Math]::Round(($Current / $Total) * 100) } else { 0 }
        
        # Calculate filled and empty blocks
        $filledBlocks = [Math]::Floor($percentage * $BarWidth / 100)
        $emptyBlocks = $BarWidth - $filledBlocks
        
        # Create the progress bar
        $progressBar = ("#" * $filledBlocks) + ("-" * $emptyBlocks)
        
        # Display the progress bar with label
        Write-Host "$Label`: [$progressBar] $percentage% ($Current/$Total)" -ForegroundColor Cyan
        
        # Log progress for audit trail
        $logger.LogInfo("$Label`: $Current/$Total complete ($percentage%)", "Progress Display")
    }
}

# Global UserInteraction instance
$Global:UserInteraction = $null

function Initialize-UserInteraction {
    $Global:UserInteraction = [UserInteraction]::new()
}

function Get-UserInteraction {
    if (-not $Global:UserInteraction) {
        throw "UserInteraction not initialized. Call Initialize-UserInteraction first."
    }
    return $Global:UserInteraction
}

# Deprecated function wrappers for backward compatibility
function Show-Menu {
    param([object]$Config, [string]$Title, [string[]]$Options, [bool]$ShowBanner = $true, [bool]$AllowBack = $false)
    $ui = Get-UserInteraction
    return $ui.ShowMenu($Config, $Title, $Options, $ShowBanner, $AllowBack)
}

function Write-Activity {
    param([string]$Message, [string]$type = 'info')
    [UserInteraction]::WriteActivity($Message, $type)
}

function Write-Table {
    param(
        [array]$Data, 
        [string[]]$Columns, 
        [string[]]$Headers, 
        [string[]]$Alignments = @(),
        [hashtable]$ColorMappings = @{}
    )
    $ui = Get-UserInteraction
    $ui.WriteTable($Data, $Columns, $Headers, $Alignments, $ColorMappings)
}

function Write-BlankLine {
    [UserInteraction]::WriteBlankLine()
}

function Read-VerifiedPassword {
    param([string]$Prompt = "Enter password")
    $ui = Get-UserInteraction
    return $ui.ReadVerifiedPassword($Prompt)
}

function Initialize-ProgressBar {
    param([int]$TotalTasks, [string]$Description = "Processing tasks")
    $ui = Get-UserInteraction
    return $ui.InitializeProgressBar($TotalTasks, $Description)
}

function Update-ProgressBar {
    param([object]$ProgressBar, [int]$CompletedTasks = 1, [string]$CurrentTask = "")
    $ui = Get-UserInteraction
    $ui.UpdateProgressBar($ProgressBar, $CompletedTasks, $CurrentTask)
}

function Complete-ProgressBar {
    param([object]$ProgressBar)
    $ui = Get-UserInteraction
    $ui.CompleteProgressBar($ProgressBar)
}

function Write-InlineProgressBar {
    param(
        [Parameter(Mandatory)]
        [int]$Current,
        [Parameter(Mandatory)]
        [int]$Total,
        [string]$Label = "Progress",
        [int]$BarWidth = 20
    )
    [UserInteraction]::WriteInlineProgressBar($Current, $Total, $Label, $BarWidth)
}

function Simple-Menu {
    param(
        [string]$Title,
        [string[]]$Options
    )
    while ($true) {
        Write-Host ""
        Write-Host $Title -ForegroundColor Cyan
        for ($i = 0; $i -lt $Options.Length; $i++) {
            Write-Host ("    [$($i+1)] $($Options[$i])")
        }
        Write-Host "    [x] Cancel" -ForegroundColor Red
        Write-Host ""
        $choice = Read-Host 'Enter choice number or x to cancel'
        $choice = $choice.ToLower().Trim()
        if ($choice -eq 'x') {
            return $null
        }
        if ([string]::IsNullOrWhiteSpace($choice)) {
            Write-Host "No option selected. Please enter a valid choice number or 'x'." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            continue
        }
        $selectedOption = if ($choice -as [int] -and $choice -ge 1 -and $choice -le $Options.Length) { $Options[$choice-1] } else { $null }
        if ($selectedOption) {
            $confirm = Read-Host "You selected '$selectedOption'. Confirm? (y/n)"
            if ($confirm -eq 'y') {
                return $selectedOption
            } else {
                Write-Host "Selection not confirmed. Please choose again." -ForegroundColor Yellow
            }
        } else {
            Write-Host "Invalid choice '$choice'. Please enter a number between 1 and $($Options.Length) or 'x'." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            continue
        }
    }
    return $null # Default return to satisfy linter
}

Export-ModuleMember -Function Initialize-UserInteraction, Get-UserInteraction, Show-Menu, Write-Activity, Write-Table, Write-BlankLine, Read-VerifiedPassword, Initialize-ProgressBar, Update-ProgressBar, Complete-ProgressBar, Write-InlineProgressBar, Simple-Menu