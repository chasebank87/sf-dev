using module core/ConfigLoader.psm1
using module core/ModuleInstaller.psm1
using module core/UserInteraction.psm1
using module core/AutomationScript.psm1
using module core/Logger.psm1
using module core/DebugHelper.psm1
using module core/SessionHelper.psm1

Initialize-ModuleInstaller
$ModuleInstaller = Get-ModuleInstaller
$ModuleInstaller.InstallRequiredModules(@('psAsciiArt', 'powershell-yaml', 'WriteAscii'))

. $PSScriptRoot/scripts/Update-TaskPasswords.ps1
. $PSScriptRoot/scripts/Update-MxlsPasswords.ps1
. $PSScriptRoot/scripts/Admin-Environment.ps1
. $PSScriptRoot/scripts/Health-Monitor.ps1

Initialize-ConfigLoader
Initialize-UserInteraction

$ConfigLoader = Get-ConfigLoader
$UserInteraction = Get-UserInteraction

# Configuration check and setup
$configPath = "$PSScriptRoot/config/dev.yaml"
$exampleConfigPath = "$PSScriptRoot/config/example.yaml"

if (-not (Test-Path $configPath)) {
    if (Test-Path $exampleConfigPath) {
        Copy-Item -Path $exampleConfigPath -Destination $configPath
        Write-Host "Created dev.yaml from example.yaml. Please update your configuration." -ForegroundColor Yellow
        exit
    } else {
        Write-Host "No configuration file found. Please create dev.yaml or example.yaml in the config directory." -ForegroundColor Red
        exit
    }
}

$yamlConfig = $ConfigLoader.ImportConfig($configPath)

Initialize-Logger -Config $yamlConfig
Initialize-DebugHelper -Config $yamlConfig
Initialize-SessionHelper -Config $yamlConfig

function Show-MainMenu {
    while ($true) {
        Clear-Host
        $category = $UserInteraction.ShowMenu($yamlConfig, 'Select Task Category', @('Quarterly Password Change', 'Monthly Close Process', 'Audit Requests', 'Patching', 'Administration'), $true, $false)
        if ($category -eq '__BACK__') { continue }
        if ($category -eq '__EXIT__') {
            $logger.LogInfo("User chose to exit from main menu", "User Action")
            [UserInteraction]::WriteActivity("Exiting application...", 'info')
            Start-Sleep -Seconds 1
            $logger.CloseSession()
            exit
        }
        if ($category -eq '__TOGGLE_DEBUG__') {
            $currentDebugStatus = if ($yamlConfig.debug) { "ENABLED" } else { "DISABLED" }
            $newDebugStatus = if ($yamlConfig.debug) { $false } else { $true }
            $newDebugStatusText = if ($newDebugStatus) { "ENABLED" } else { "DISABLED" }
            [UserInteraction]::WriteActivity("Current Debug Mode: $currentDebugStatus", 'info')
            [UserInteraction]::WriteActivity("Switching Debug Mode to: $newDebugStatusText", 'info')
            try {
                # Update config and reload
                $yamlConfig = $ConfigLoader.UpdateDebugSetting($configPath, $newDebugStatus)
                
                # Reinitialize all components that depend on debug settings
                [UserInteraction]::WriteActivity("Reinitializing components with new debug setting...", 'info')
                Initialize-DebugHelper -Config $yamlConfig
                Initialize-SessionHelper -Config $yamlConfig
                
                [UserInteraction]::WriteActivity("Debug mode successfully updated to: $newDebugStatusText", 'info')
                Start-Sleep -Seconds 1
            } catch {
                [UserInteraction]::WriteActivity("Failed to update debug mode: $_", 'error')
                Start-Sleep -Seconds 2
            }
            continue
        }
        switch ($category) {
            'Quarterly Password Change' {
                Show-QuarterlyMenu
            }
            'Monthly Close Process' {
                [UserInteraction]::WriteActivity("No monthly close scripts configured yet.", 'info')
                Start-Sleep -Seconds 2
                [UserInteraction]::WriteBlankLine()
                [UserInteraction]::WriteActivity("What would you like to do?", 'info')
                $choice = Read-Host "Enter '1' to return to main menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Message Choice")
                switch ($choice) {
                    '1' {
                        $logger.LogInfo("User chose to return to main menu", "User Action")
                        [UserInteraction]::WriteActivity("Returning to main menu...", 'info')
                        Start-Sleep -Seconds 1
                        continue
                    }
                    'q' {
                        $logger.LogInfo("User chose to quit application", "User Action")
                        [UserInteraction]::WriteActivity("Exiting application...", 'info')
                        Start-Sleep -Seconds 1
                        $logger.CloseSession()
                        exit
                    }
                    default {
                        $logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        [UserInteraction]::WriteActivity("Invalid choice. Returning to main menu...", 'warning')
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
        $automation = $UserInteraction.ShowMenu($yamlConfig, 'Quarterly Password Change Automations', @('Update Task Passwords', 'Update MXLS Passwords'), $true, $true)
        if ($automation -eq '__BACK__') {
            $logger.LogMenuSelection("Go Back", "Quarterly Menu")
            return
        }
        if ($automation -eq '__EXIT__') {
            $logger.LogInfo("User chose to exit from quarterly menu", "User Action")
            [UserInteraction]::WriteActivity("Exiting application...", 'info')
            Start-Sleep -Seconds 1
            $logger.CloseSession()
            exit
        }
        switch ($automation) {
            'Update Task Passwords' {
                $logger.LogAutomationStart("Update Task Passwords")
                Invoke-UpdateTaskPasswords -Config $yamlConfig
                $logger.LogAutomationEnd("Update Task Passwords", $true)
                [UserInteraction]::WriteBlankLine()
                [UserInteraction]::WriteActivity("Automation completed. What would you like to do?", 'info')
                $choice = Read-Host "Enter '1' to return to quarterly menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Automation Choice")
                switch ($choice) {
                    '1' {
                        $logger.LogInfo("User chose to return to quarterly menu", "User Action")
                        [UserInteraction]::WriteActivity("Returning to quarterly menu...", 'info')
                        Start-Sleep -Seconds 1
                        continue
                    }
                    'q' {
                        $logger.LogInfo("User chose to quit application", "User Action")
                        [UserInteraction]::WriteActivity("Exiting application...", 'info')
                        Start-Sleep -Seconds 1
                        $logger.CloseSession()
                        exit
                    }
                    default {
                        $logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        [UserInteraction]::WriteActivity("Invalid choice. Returning to quarterly menu...", 'warning')
                        Start-Sleep -Seconds 2
                        continue
                    }
                }
            }
            'Update MXLS Passwords' {
                $logger.LogAutomationStart("Update MXLS Passwords")
                Invoke-UpdateMxlsPasswords -Config $yamlConfig
                $logger.LogAutomationEnd("Update MXLS Passwords", $true)
                [UserInteraction]::WriteBlankLine()
                [UserInteraction]::WriteActivity("Automation completed. What would you like to do?", 'info')
                $choice = Read-Host "Enter '1' to return to quarterly menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Automation Choice")
                switch ($choice) {
                    '1' {
                        $logger.LogInfo("User chose to return to quarterly menu", "User Action")
                        [UserInteraction]::WriteActivity("Returning to quarterly menu...", 'info')
                        Start-Sleep -Seconds 1
                        continue
                    }
                    'q' {
                        $logger.LogInfo("User chose to quit application", "User Action")
                        [UserInteraction]::WriteActivity("Exiting application...", 'info')
                        Start-Sleep -Seconds 1
                        $logger.CloseSession()
                        exit
                    }
                    default {
                        $logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        [UserInteraction]::WriteActivity("Invalid choice. Returning to quarterly menu...", 'warning')
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
        $automation = $UserInteraction.ShowMenu($yamlConfig, 'Audit Requests', @(), $true, $true)
        if ($automation -eq '__BACK__') {
            $logger.LogMenuSelection("Go Back", "Audit Menu")
            return
        }
        if ($automation -eq '__EXIT__') {
            $logger.LogInfo("User chose to exit from audit menu", "User Action")
            [UserInteraction]::WriteActivity("Exiting application...", 'info')
            Start-Sleep -Seconds 1
            $logger.CloseSession()
            exit
        }
        [UserInteraction]::WriteActivity("No audit automations configured yet.", 'info')
        Start-Sleep -Seconds 2
        [UserInteraction]::WriteBlankLine()
        [UserInteraction]::WriteActivity("What would you like to do?", 'info')
        $choice = Read-Host "Enter '1' to return to audit menu or 'q' to quit"
        $logger.LogUserInput($choice, "Post-Message Choice")
        switch ($choice) {
            '1' {
                $logger.LogInfo("User chose to return to audit menu", "User Action")
                [UserInteraction]::WriteActivity("Returning to audit menu...", 'info')
                Start-Sleep -Seconds 1
                continue
            }
            'q' {
                $logger.LogInfo("User chose to quit application", "User Action")
                [UserInteraction]::WriteActivity("Exiting application...", 'info')
                Start-Sleep -Seconds 1
                $logger.CloseSession()
                exit
            }
            default {
                $logger.LogWarning("Invalid choice entered: $choice", "User Input")
                [UserInteraction]::WriteActivity("Invalid choice. Returning to audit menu...", 'warning')
                Start-Sleep -Seconds 2
                continue
            }
        }
    }
}

function Show-PatchingMenu {
    while ($true) {
        Clear-Host
        $automation = $UserInteraction.ShowMenu($yamlConfig, 'Patching Automations', @(), $true, $true)
        if ($automation -eq '__BACK__') {
            $logger.LogMenuSelection("Go Back", "Patching Menu")
            return
        }
        if ($automation -eq '__EXIT__') {
            $logger.LogInfo("User chose to exit from patching menu", "User Action")
            [UserInteraction]::WriteActivity("Exiting application...", 'info')
            Start-Sleep -Seconds 1
            $logger.CloseSession()
            exit
        }
        [UserInteraction]::WriteActivity("No patching automations configured yet.", 'info')
        Start-Sleep -Seconds 2
        [UserInteraction]::WriteBlankLine()
        [UserInteraction]::WriteActivity("What would you like to do?", 'info')
        $choice = Read-Host "Enter '1' to return to patching menu or 'q' to quit"
        $logger.LogUserInput($choice, "Post-Message Choice")
        switch ($choice) {
            '1' {
                $logger.LogInfo("User chose to return to patching menu", "User Action")
                [UserInteraction]::WriteActivity("Returning to patching menu...", 'info')
                Start-Sleep -Seconds 1
                continue
            }
            'q' {
                $logger.LogInfo("User chose to quit application", "User Action")
                [UserInteraction]::WriteActivity("Exiting application...", 'info')
                Start-Sleep -Seconds 1
                $logger.CloseSession()
                exit
            }
            default {
                $logger.LogWarning("Invalid choice entered: $choice", "User Input")
                [UserInteraction]::WriteActivity("Invalid choice. Returning to patching menu...", 'warning')
                Start-Sleep -Seconds 2
                continue
            }
        }
    }
}

function Show-AdminMenu {
    while ($true) {
        Clear-Host
        $adminOption = $UserInteraction.ShowMenu($yamlConfig, 'Administration', @('Start Environment', 'Stop Environment', 'Health Monitor'), $true, $true)
        if ($adminOption -eq '__BACK__') {
            $logger.LogMenuSelection("Go Back", "Admin Menu")
            return
        }
        if ($adminOption -eq '__EXIT__') {
            $logger.LogInfo("User chose to exit from administration menu", "User Action")
            [UserInteraction]::WriteActivity("Exiting application...", 'info')
            Start-Sleep -Seconds 1
            $logger.CloseSession()
            exit
        }
        switch ($adminOption) {
            'Start Environment' {
                $logger.LogAutomationStart("Start Environment")
                Invoke-AdminEnvironment -Config $yamlConfig -Mode 'Start'
                $logger.LogAutomationEnd("Start Environment", $true)
                [UserInteraction]::WriteBlankLine()
                [UserInteraction]::WriteActivity("Automation completed. What would you like to do?", 'info')
                $choice = Read-Host "Enter '1' to return to administration menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Automation Choice")
                switch ($choice) {
                    '1' {
                        $logger.LogInfo("User chose to return to administration menu", "User Action")
                        [UserInteraction]::WriteActivity("Returning to administration menu...", 'info')
                        Start-Sleep -Seconds 1
                        continue
                    }
                    'q' {
                        $logger.LogInfo("User chose to quit application", "User Action")
                        [UserInteraction]::WriteActivity("Exiting application...", 'info')
                        Start-Sleep -Seconds 1
                        $logger.CloseSession()
                        exit
                    }
                    default {
                        $logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        [UserInteraction]::WriteActivity("Invalid choice. Returning to administration menu...", 'warning')
                        Start-Sleep -Seconds 2
                        continue
                    }
                }
            }
            'Stop Environment' {
                $logger.LogAutomationStart("Stop Environment")
                Invoke-AdminEnvironment -Config $yamlConfig -Mode 'Stop'
                $logger.LogAutomationEnd("Stop Environment", $true)
                [UserInteraction]::WriteBlankLine()
                [UserInteraction]::WriteActivity("Automation completed. What would you like to do?", 'info')
                $choice = Read-Host "Enter '1' to return to administration menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Automation Choice")
                switch ($choice) {
                    '1' {
                        $logger.LogInfo("User chose to return to administration menu", "User Action")
                        [UserInteraction]::WriteActivity("Returning to administration menu...", 'info')
                        Start-Sleep -Seconds 1
                        continue
                    }
                    'q' {
                        $logger.LogInfo("User chose to quit application", "User Action")
                        [UserInteraction]::WriteActivity("Exiting application...", 'info')
                        Start-Sleep -Seconds 1
                        $logger.CloseSession()
                        exit
                    }
                    default {
                        $logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        [UserInteraction]::WriteActivity("Invalid choice. Returning to administration menu...", 'warning')
                        Start-Sleep -Seconds 2
                        continue
                    }
                }
            }
            'Health Monitor' {
                $logger.LogAutomationStart("Health Monitor")
                $result = Invoke-HealthMonitor -Config $yamlConfig
                
                # Health Monitor now handles its own confirmation and returns either '__BACK__' or '__EXIT__'
                if ($result -eq '__BACK__') {
                    # User chose to go back to menu
                    $logger.LogInfo("User chose to return to administration menu from health monitor", "User Action")
                    continue
                } elseif ($result -eq '__EXIT__') {
                    # User chose to exit application
                    $logger.LogInfo("User chose to exit application from health monitor", "User Action")
                    [UserInteraction]::WriteActivity("Exiting application...", 'info')
                    Start-Sleep -Seconds 1
                    $logger.CloseSession()
                    exit
                } else {
                    # For any other result, log completion and continue to menu
                    $logger.LogAutomationEnd("Health Monitor", $result)
                    continue
                }
            }
        }
    }
}

# Set up exit handler to close logger and cleanup sessions
try {
    Show-MainMenu
} finally {
    # Cleanup SessionHelper
    try {
        Remove-AllManagedSessions
    } catch {
        # Ignore cleanup errors during exit
    }
    
    # Close logger
    if ($logger) {
        $logger.CloseSession()
    }
} 