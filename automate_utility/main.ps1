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

# Configuration check and setup
$configPath = "$PSScriptRoot/config/dev.yaml"
$exampleConfigPath = "$PSScriptRoot/config/example.yaml"

function Test-ConfigurationSetup {
    # Check if dev.yaml exists
    if (-not (Test-Path $configPath)) {
        Write-Host "`n CONFIGURATION ERROR" -ForegroundColor Red
        Write-Host "===============================================" -ForegroundColor Red
        Write-Host "The configuration file 'config/dev.yaml' is missing!" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To fix this issue:" -ForegroundColor Cyan
        Write-Host "1. Copy the example configuration file:" -ForegroundColor White
        Write-Host "   Copy-Item '$exampleConfigPath' '$configPath'" -ForegroundColor Gray
        Write-Host ""
        Write-Host "2. Edit the configuration file with your actual values:" -ForegroundColor White
        Write-Host "   notepad '$configPath'  # Windows" -ForegroundColor Gray
        Write-Host "   code '$configPath'     # VS Code" -ForegroundColor Gray
        Write-Host "   nano '$configPath'     # Linux/macOS" -ForegroundColor Gray
        Write-Host ""
        Write-Host "3. Update the following required fields:" -ForegroundColor Yellow
        Write-Host "   - service_account: Your actual service account name" -ForegroundColor White
        Write-Host "   - servers: Your actual server list" -ForegroundColor White
        Write-Host "   - mxls_template_servers: Your MXLS template servers" -ForegroundColor White
        Write-Host "   - mxls_automation.service_account: Your MXLS service account" -ForegroundColor White
        Write-Host ""
        Write-Host "4. Restart the application after configuration is complete." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "For more information, see the README.md file." -ForegroundColor Gray
        Write-Host "===============================================" -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    # Check if example.yaml exists (for reference)
    if (-not (Test-Path $exampleConfigPath)) {
        Write-Host "`n  WARNING" -ForegroundColor Yellow
        Write-Host "The example configuration file 'config/example.yaml' is missing." -ForegroundColor Yellow
        Write-Host "This file should be available for reference. Please check your installation." -ForegroundColor Yellow
        Write-Host ""
    }
    
    Write-Host "Configuration file found: $configPath" -ForegroundColor Green
}

# Run configuration check
Test-ConfigurationSetup

# Load config
$yamlConfig = Import-Config -ConfigPath $configPath

# Initialize logger and debug helper with config
Initialize-Logger -Config $yamlConfig
Initialize-DebugHelper -Config $yamlConfig
$logger = Get-Logger
$debugHelper = Get-DebugHelper

$logger.LogInfo("Configuration loaded from: $configPath", "Configuration")
if ($debugHelper.IsDebug()) {
    $logger.LogInfo("DEBUG MODE ENABLED - Commands will be logged but not executed", "Debug")
    Write-Host "DEBUG MODE ENABLED - Commands will be logged but not executed" -ForegroundColor Red
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        $category = Show-Menu -Config $yamlConfig -Title 'Select Task Category' -Options @('Quarterly Password Change', 'Monthly Close Process', 'Audit Requests', 'Patching', 'Administration') -ShowBanner:$true -AllowBack:$false
        if ($category -eq '__BACK__') { continue }
        if ($category -eq '__EXIT__') {
            $logger.LogInfo("User chose to exit from main menu", "User Action")
            Write-Activity "Exiting application..." -type 'info'
            Start-Sleep -Seconds 1
            $logger.CloseSession()
            exit
        }
        if ($category -eq '__TOGGLE_DEBUG__') {
                $currentDebugStatus = if ($yamlConfig.debug) { "ENABLED" } else { "DISABLED" }
                $newDebugStatus = if ($yamlConfig.debug) { $false } else { $true }
                $newDebugStatusText = if ($newDebugStatus) { "ENABLED" } else { "DISABLED" }
                
                Write-Activity "Current Debug Mode: $currentDebugStatus" -type 'info'
                Write-Activity "Switching Debug Mode to: $newDebugStatusText" -type 'info'
                
                try {
                    # Update the configuration file
                $yamlConfig = Update-DebugSetting -ConfigPath $configPath -DebugEnabled $newDebugStatus
                    
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
            continue
        }
        
        $logger.LogMenuSelection($category, "Main Menu")
        
        switch ($category) {
            'Quarterly Password Change' {
                Show-QuarterlyMenu
            }
            'Monthly Close Process' {
                Write-Activity "No monthly close scripts configured yet." -type 'info'
                Start-Sleep -Seconds 2
                
                # After showing message, ask user what to do next
                Write-BlankLine
                Write-Activity "What would you like to do?" -type 'info'
                $choice = Read-Host "Enter '1' to return to main menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Message Choice")
                
                switch ($choice) {
                    '1' { 
                        $logger.LogInfo("User chose to return to main menu", "User Action")
                        Write-Activity "Returning to main menu..." -type 'info'
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
                        Write-Activity "Invalid choice. Returning to main menu..." -type 'warning'
                        Start-Sleep -Seconds 2
                        continue 
                    }
                }
            }
            'Audit Requests' {
                Show-AuditMenu
            }
            'Patching' {
                Show-PatchingMenu
            }
            'Administration' {
                Show-AdminMenu
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
                $choice = Read-Host "Enter '1' to return to quarterly menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Automation Choice")
                
                switch ($choice) {
                    '1' { 
                        $logger.LogInfo("User chose to return to quarterly menu", "User Action")
                        Write-Activity "Returning to quarterly menu..." -type 'info'
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
                        Write-Activity "Invalid choice. Returning to quarterly menu..." -type 'warning'
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
                $choice = Read-Host "Enter '1' to return to quarterly menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Automation Choice")
                
                switch ($choice) {
                    '1' { 
                        $logger.LogInfo("User chose to return to quarterly menu", "User Action")
                        Write-Activity "Returning to quarterly menu..." -type 'info'
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
                        Write-Activity "Invalid choice. Returning to quarterly menu..." -type 'warning'
                        Start-Sleep -Seconds 2
                        continue 
                    }
                }
            }
        }
    }
}

function Show-AuditMenu {
    while ($true) {
        Clear-Host
        $automation = Show-Menu -Config $yamlConfig -Title 'Audit Requests' -Options @() -ShowBanner:$true -AllowBack:$true
        if ($automation -eq '__BACK__') { 
            $logger.LogMenuSelection("Go Back", "Audit Menu")
            return 
        }
        
        $logger.LogMenuSelection($automation, "Audit Menu")
        
        # No automations configured yet
        Write-Activity "No audit automations configured yet." -type 'info'
        Start-Sleep -Seconds 2
        
        # After showing message, ask user what to do next
        Write-BlankLine
        Write-Activity "What would you like to do?" -type 'info'
        $choice = Read-Host "Enter '1' to return to audit menu or 'q' to quit"
        $logger.LogUserInput($choice, "Post-Message Choice")
        
        switch ($choice) {
            '1' { 
                $logger.LogInfo("User chose to return to audit menu", "User Action")
                Write-Activity "Returning to audit menu..." -type 'info'
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
                Write-Activity "Invalid choice. Returning to audit menu..." -type 'warning'
                Start-Sleep -Seconds 2
                continue 
            }
        }
    }
}

function Show-PatchingMenu {
    while ($true) {
        Clear-Host
        $automation = Show-Menu -Config $yamlConfig -Title 'Patching Automations' -Options @() -ShowBanner:$true -AllowBack:$true
        if ($automation -eq '__BACK__') { 
            $logger.LogMenuSelection("Go Back", "Patching Menu")
            return 
        }
        
        $logger.LogMenuSelection($automation, "Patching Menu")
        
        # No automations configured yet
        Write-Activity "No patching automations configured yet." -type 'info'
        Start-Sleep -Seconds 2
        
        # After showing message, ask user what to do next
        Write-BlankLine
        Write-Activity "What would you like to do?" -type 'info'
        $choice = Read-Host "Enter '1' to return to patching menu or 'q' to quit"
        $logger.LogUserInput($choice, "Post-Message Choice")
        
        switch ($choice) {
            '1' { 
                $logger.LogInfo("User chose to return to patching menu", "User Action")
                Write-Activity "Returning to patching menu..." -type 'info'
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
                Write-Activity "Invalid choice. Returning to patching menu..." -type 'warning'
                Start-Sleep -Seconds 2
                continue 
            }
        }
    }
}

function Show-AdminMenu {
    while ($true) {
        Clear-Host
        $adminOption = Show-Menu -Config $yamlConfig -Title 'Administration' -Options @('Start Environment', 'Stop Environment', 'Health Monitor') -ShowBanner:$true -AllowBack:$true
        if ($adminOption -eq '__BACK__' -or $adminOption -eq '__EXIT__') { return }
        switch ($adminOption) {
            'Start Environment' {
                $logger.LogAutomationStart("Start Environment")
                Import-Module "$PSScriptRoot/scripts/Admin-Environment.psm1" -Force
                Invoke-AdminEnvironment -Config $yamlConfig -Mode 'Start'
                $logger.LogAutomationEnd("Start Environment", $true)
                
                # After running, ask user what to do next
                Write-BlankLine
                Write-Activity "Automation completed. What would you like to do?" -type 'info'
                $choice = Read-Host "Enter '1' to return to administration menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Automation Choice")
                
                switch ($choice) {
                    '1' { 
                        $logger.LogInfo("User chose to return to administration menu", "User Action")
                        Write-Activity "Returning to administration menu..." -type 'info'
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
                        Write-Activity "Invalid choice. Returning to administration menu..." -type 'warning'
                        Start-Sleep -Seconds 2
                        continue 
                    }
                }
            }
            'Stop Environment' {
                $logger.LogAutomationStart("Stop Environment")
                Import-Module "$PSScriptRoot/scripts/Admin-Environment.psm1" -Force
                Invoke-AdminEnvironment -Config $yamlConfig -Mode 'Stop'
                $logger.LogAutomationEnd("Stop Environment", $true)
                
                # After running, ask user what to do next
                Write-BlankLine
                Write-Activity "Automation completed. What would you like to do?" -type 'info'
                $choice = Read-Host "Enter '1' to return to administration menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Automation Choice")
                
                switch ($choice) {
                    '1' { 
                        $logger.LogInfo("User chose to return to administration menu", "User Action")
                        Write-Activity "Returning to administration menu..." -type 'info'
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
                        Write-Activity "Invalid choice. Returning to administration menu..." -type 'warning'
                        Start-Sleep -Seconds 2
                        continue 
                    }
                }
            }
            'Health Monitor' {
                $logger.LogAutomationStart("Health Monitor")
                Import-Module "$PSScriptRoot/scripts/Health-Monitor.psm1" -Force
                $result = Invoke-HealthMonitor -Config $yamlConfig
                $logger.LogAutomationEnd("Health Monitor", $result)
                
                # After running, ask user what to do next
                Write-BlankLine
                Write-Activity "Health monitoring completed. What would you like to do?" -type 'info'
                $choice = Read-Host "Enter '1' to return to administration menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Automation Choice")
                
                switch ($choice) {
                    '1' { 
                        $logger.LogInfo("User chose to return to administration menu", "User Action")
                        Write-Activity "Returning to administration menu..." -type 'info'
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
                        Write-Activity "Invalid choice. Returning to administration menu..." -type 'warning'
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