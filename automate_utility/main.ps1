using module ./core/AutomationScript.psm1
using module ./scripts/Update-TaskPasswords.psm1
using module ./scripts/Update-MxlsPasswords.psm1
using module ./core/ConfigLoader.psm1
using module ./core/UserInteraction.psm1
using module ./core/Logger.psm1
using module ./core/DebugHelper.psm1

# Entry point for automation suite
Import-Module -Name "$PSScriptRoot/core/ModuleInstaller.psm1"
Install-RequiredModules -ModuleNames @('psAsciiArt', 'powershell-yaml')
Import-Module -Name "$PSScriptRoot/core/ConfigLoader.psm1"
Import-Module -Name "$PSScriptRoot/core/UserInteraction.psm1"
Import-Module -Name "$PSScriptRoot/core/Logger.psm1"
Import-Module -Name "$PSScriptRoot/core/DebugHelper.psm1"

# Load config
$yamlConfig = Import-Config -ConfigPath "$PSScriptRoot/config/dev.yaml"

# Initialize logger and debug helper with config
Initialize-Logger -Config $yamlConfig
Initialize-DebugHelper -Config $yamlConfig
$logger = Get-Logger
$debugHelper = Get-DebugHelper

$logger.LogInfo("Configuration loaded from: $PSScriptRoot/config/dev.yaml", "Configuration")
if ($debugHelper.IsDebug()) {
    $logger.LogInfo("DEBUG MODE ENABLED - Commands will be logged but not executed", "Debug")
    Write-Host "DEBUG MODE ENABLED - Commands will be logged but not executed" -ForegroundColor Red
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        $category = Show-Menu -Config $yamlConfig -Title 'Select Task Category' -Options @('Quarterly Password Change', 'Toggle Debug Mode', 'Exit') -ShowBanner:$true -AllowBack:$false
        if ($category -eq '__BACK__') { continue }
        
        $logger.LogMenuSelection($category, "Main Menu")
        
        switch ($category) {
            'Quarterly Password Change' {
                Show-QuarterlyMenu
            }
            'Toggle Debug Mode' {
                $currentDebugStatus = if ($yamlConfig.debug) { "ENABLED" } else { "DISABLED" }
                $newDebugStatus = if ($yamlConfig.debug) { $false } else { $true }
                $newDebugStatusText = if ($newDebugStatus) { "ENABLED" } else { "DISABLED" }
                
                Write-Activity "Current Debug Mode: $currentDebugStatus" -type 'info'
                Write-Activity "Switching Debug Mode to: $newDebugStatusText" -type 'info'
                
                try {
                    # Update the configuration file
                    $yamlConfig = Update-DebugSetting -ConfigPath "$PSScriptRoot/config/dev.yaml" -DebugEnabled $newDebugStatus
                    
                    # Update the global debug helper
                    $Global:DebugHelper = Get-DebugHelper
                    
                    Write-Activity "Debug Mode successfully switched to: $newDebugStatusText" -type 'info'
                    $logger.LogInfo("Debug Mode toggled from $currentDebugStatus to $newDebugStatusText", "Configuration")
                    
                    # Show updated status
                    Start-Sleep -Seconds 2
                    Clear-Host
                    if ($newDebugStatus) {
                        Write-Host "DEBUG MODE ENABLED - Commands will be logged but not executed" -ForegroundColor Red
                        $logger.LogInfo("DEBUG MODE ENABLED - Commands will be logged but not executed", "Debug")
                    } else {
                        Write-Host "DEBUG MODE DISABLED - Commands will be executed normally" -ForegroundColor Green
                        $logger.LogInfo("DEBUG MODE DISABLED - Commands will be executed normally", "Debug")
                    }
                    Start-Sleep -Seconds 2
                    
                } catch {
                    Write-Activity "Failed to toggle debug mode: $($_.Exception.Message)" -type 'error'
                    $logger.LogError("Failed to toggle debug mode: $($_.Exception.Message)", "Configuration")
                    Start-Sleep -Seconds 3
                }
            }
            'Exit' {
                $logger.LogInfo("User chose to exit from main menu", "User Action")
                Write-Activity "Exiting application..." -type 'info'
                Start-Sleep -Seconds 1
                $logger.CloseSession()
                exit
            }
        }
    }
}

function Show-QuarterlyMenu {
    while ($true) {
        Clear-Host
        $automation = Show-Menu -Config $yamlConfig -Title 'Quarterly Password Change Automations' -Options @('Update Task Passwords', 'Update MXLS Passwords') -ShowBanner:$true -AllowBack:$true
        if ($automation -eq '__BACK__') { 
            $logger.LogMenuSelection("Go Back", "Quarterly Menu")
            return 
        }
        
        $logger.LogMenuSelection($automation, "Quarterly Menu")
        
        switch ($automation) {
            'Update Task Passwords' {
                $logger.LogAutomationStart("Update Task Passwords")
                $script = [UpdateTaskPasswords]::new($yamlConfig)
                $script.Run()
                $logger.LogAutomationEnd("Update Task Passwords", $true)
                
                # After running, ask user what to do next
                Write-BlankLine
                Write-Activity "Automation completed. What would you like to do?" -type 'info'
                $choice = Read-Host "Enter '1' to return to menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Automation Choice")
                
                switch ($choice) {
                    '1' { 
                        $logger.LogInfo("User chose to return to menu", "User Action")
                        Write-Activity "Returning to menu..." -type 'info'
                        Start-Sleep -Seconds 1
                        continue 
                    }
                    'q' { 
                        $logger.LogInfo("User chose to quit application", "User Action")
                        Write-Activity "Exiting application..." -type 'info'
                        Start-Sleep -Seconds 1
                        $logger.CloseSession()
                        exit 
                    }
                    default { 
                        $logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        Write-Activity "Invalid choice. Returning to menu..." -type 'warning'
                        Start-Sleep -Seconds 2
                        continue 
                    }
                }
            }
            'Update MXLS Passwords' {
                $logger.LogAutomationStart("Update MXLS Passwords")
                $script = [UpdateMxlsPasswords]::new($yamlConfig)
                $script.Run()
                $logger.LogAutomationEnd("Update MXLS Passwords", $true)
                
                # After running, ask user what to do next
                Write-BlankLine
                Write-Activity "Automation completed. What would you like to do?" -type 'info'
                $choice = Read-Host "Enter '1' to return to menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Automation Choice")
                
                switch ($choice) {
                    '1' { 
                        $logger.LogInfo("User chose to return to menu", "User Action")
                        Write-Activity "Returning to menu..." -type 'info'
                        Start-Sleep -Seconds 1
                        continue 
                    }
                    'q' { 
                        $logger.LogInfo("User chose to quit application", "User Action")
                        Write-Activity "Exiting application..." -type 'info'
                        Start-Sleep -Seconds 1
                        $logger.CloseSession()
                        exit 
                    }
                    default { 
                        $logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        Write-Activity "Invalid choice. Returning to menu..." -type 'warning'
                        Start-Sleep -Seconds 2
                        continue 
                    }
                }
            }
        }
    }
}

# Set up exit handler to close logger
try {
    Show-MainMenu
} finally {
    if ($logger) {
        $logger.CloseSession()
    }
} 