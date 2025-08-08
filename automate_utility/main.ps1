using module core/ConfigLoader.psm1
using module core/ModuleInstaller.psm1
using module core/UserInteraction.psm1
using module core/AutomationScript.psm1
using module core/Logger.psm1
using module core/DebugHelper.psm1
using module core/SessionHelper.psm1

function Test-AdministrativePrivileges {
    try {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Show-AdminPrivilegeWarning {
    param([object]$UserInteraction)
    
    Clear-Host
    $UserInteraction.ShowScriptTitle("Administrative Privileges Required")
    $UserInteraction.WriteBlankLine()
    $UserInteraction.WriteActivity("This application requires administrative privileges to perform certain operations.", 'warning')
    $UserInteraction.WriteBlankLine()
    $UserInteraction.WriteActivity("Some features may not work correctly without admin rights:", 'info')
    $UserInteraction.WriteActivity(" Service password updates", 'info')
    $UserInteraction.WriteActivity(" Service start/stop operations", 'info')
    $UserInteraction.WriteActivity(" Registry modifications", 'info')
    $UserInteraction.WriteActivity(" System configuration changes", 'info')
    $UserInteraction.WriteBlankLine()
    $UserInteraction.WriteActivity("Current privileges: Standard User", 'warning')
    $UserInteraction.WriteBlankLine()
    $UserInteraction.WriteActivity("To run with administrative privileges:", 'info')
    $UserInteraction.WriteActivity("1. Right-click on PowerShell", 'info')
    $UserInteraction.WriteActivity("2. Select 'Run as administrator'", 'info')
    $UserInteraction.WriteActivity("3. Navigate to this directory", 'info')
    $UserInteraction.WriteActivity("4. Run the script again", 'info')
    $UserInteraction.WriteBlankLine()
    $UserInteraction.WriteActivity("Press any key to continue anyway (some features may fail)...", 'warning')
    $null = Read-Host
}

Initialize-ModuleInstaller
$ModuleInstaller = Get-ModuleInstaller
$ModuleInstaller.InstallRequiredModules(@('psAsciiArt', 'powershell-yaml', 'WriteAscii'))

. $PSScriptRoot/scripts/Update-TaskPasswords.ps1
. $PSScriptRoot/scripts/Update-MxlsPasswords.ps1
. $PSScriptRoot/scripts/Admin-Environment.ps1
. $PSScriptRoot/scripts/Health-Monitor.ps1
. $PSScriptRoot/scripts/Update-ServiceAccountServices.ps1
. $PSScriptRoot/scripts/Enable-DisableTaskSchedulerJobs.ps1

# Initialize core components using singleton pattern
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

# Initialize singletons with configuration
Initialize-Logger -Config $yamlConfig
Initialize-DebugHelper -Config $yamlConfig
Initialize-SessionHelper -Config $yamlConfig

# Get singleton instances once at the top level
$Logger = [Logger]::GetInstance()
$UserInteraction = [UserInteraction]::GetInstance()
$DebugHelper = [DebugHelper]::GetInstance()

# Check for administrative privileges
if (-not (Test-AdministrativePrivileges)) {
    $Logger.LogWarning("Application started without administrative privileges", "Privilege Check")
    Show-AdminPrivilegeWarning -UserInteraction $UserInteraction
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        $category = $UserInteraction.ShowMenu($yamlConfig, 'Select Task Category', @('Quarterly Password Change', 'Monthly Close Process', 'Audit Requests', 'Patching', 'Administration'), $true, $false)
        if ($category -eq '__BACK__') { continue }
        if ($category -eq '__EXIT__') {
            $logger = [Logger]::GetInstance()
            $logger.LogInfo("User chose to exit from main menu", "User Action")
            $ui = [UserInteraction]::GetInstance()
            $ui.WriteActivity("Exiting application...", 'info')
            Start-Sleep -Seconds 1
            $logger.CloseSession()
            exit
        }
        if ($category -eq '__TOGGLE_DEBUG__') {
            $currentDebugStatus = if ($yamlConfig.debug) { "ENABLED" } else { "DISABLED" }
            $newDebugStatus = if ($yamlConfig.debug) { $false } else { $true }
            $newDebugStatusText = if ($newDebugStatus) { "ENABLED" } else { "DISABLED" }
            $ui = [UserInteraction]::GetInstance()
            $ui.WriteActivity("Current Debug Mode: $currentDebugStatus", 'info')
            $ui.WriteActivity("Switching Debug Mode to: $newDebugStatusText", 'info')
            try {
                # Update config file and reload
                $yamlConfig = $ConfigLoader.UpdateDebugSetting($configPath, $newDebugStatus)
                
                # Reload config from file to ensure we have the latest
                $yamlConfig = $ConfigLoader.ImportConfig($configPath)
                
                # Reinitialize all components that depend on debug settings
                $ui.WriteActivity("Reinitializing components with new debug setting...", 'info')
                
                # Reset singletons to ensure fresh instances
                [DebugHelper]::Reset()
                
                Initialize-DebugHelper -Config $yamlConfig
                Initialize-SessionHelper -Config $yamlConfig
                
                # Reinitialize top-level variables to get fresh instances
                $DebugHelper = [DebugHelper]::GetInstance()
                $SessionHelper = Get-SessionHelper
                
                # Also refresh Logger and UserInteraction to ensure consistency
                $Logger = [Logger]::GetInstance()
                $UserInteraction = [UserInteraction]::GetInstance()
                
                # Verify debug mode is actually updated
                $ui.WriteActivity("Debug mode verification: $($DebugHelper.IsDebug())", 'info')
                
                $ui.WriteActivity("Debug mode successfully updated to: $newDebugStatusText", 'info')
                Start-Sleep -Seconds 1
            } catch {
                $ui.WriteActivity("Failed to update debug mode: $_", 'error')
                Start-Sleep -Seconds 2
            }
            continue
        }
        switch ($category) {
            'Quarterly Password Change' {
                Show-QuarterlyMenu
            }
            'Monthly Close Process' {
                $ui = [UserInteraction]::GetInstance()
                $logger = [Logger]::GetInstance()
                $ui.WriteActivity("No monthly close scripts configured yet.", 'info')
                Start-Sleep -Seconds 2
                $ui.WriteBlankLine()
                $ui.WriteActivity("What would you like to do?", 'info')
                $choice = Read-Host "Enter '1' to return to main menu or 'q' to quit"
                $logger.LogUserInput($choice, "Post-Message Choice")
                switch ($choice) {
                    '1' {
                        $logger.LogInfo("User chose to return to main menu", "User Action")
                        $ui.WriteActivity("Returning to main menu...", 'info')
                        Start-Sleep -Seconds 1
                        continue
                    }
                    'q' {
                        $logger.LogInfo("User chose to quit application", "User Action")
                        $ui.WriteActivity("Exiting application...", 'info')
                        Start-Sleep -Seconds 1
                        $logger.CloseSession()
                        exit
                    }
                    default {
                        $logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        $ui.WriteActivity("Invalid choice. Returning to main menu...", 'warning')
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
        $automation = $UserInteraction.ShowMenu($yamlConfig, 'Quarterly Password Change Automations', @('Update Task Passwords', 'Update MXLS Passwords', 'Update Service Account Services'), $true, $true)
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
                $Logger.LogAutomationStart("Update Task Passwords")
                Invoke-UpdateTaskPasswords -Config $yamlConfig -DebugHelper $DebugHelper
                $Logger.LogAutomationEnd("Update Task Passwords", $true)
                $UserInteraction.WriteBlankLine()
                $UserInteraction.WriteActivity("Automation completed. What would you like to do?", 'info')
                $choice = Read-Host "Enter '1' to return to quarterly menu or 'q' to quit"
                $Logger.LogUserInput($choice, "Post-Automation Choice")
                switch ($choice) {
                    '1' {
                        $Logger.LogInfo("User chose to return to quarterly menu", "User Action")
                        $UserInteraction.WriteActivity("Returning to quarterly menu...", 'info')
                        Start-Sleep -Seconds 1
                        continue
                    }
                    'q' {
                        $Logger.LogInfo("User chose to quit application", "User Action")
                        $UserInteraction.WriteActivity("Exiting application...", 'info')
                        Start-Sleep -Seconds 1
                        $Logger.CloseSession()
                        exit
                    }
                    default {
                        $Logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        $UserInteraction.WriteActivity("Invalid choice. Returning to quarterly menu...", 'warning')
                        Start-Sleep -Seconds 2
                        continue
                    }
                }
            }
            'Update MXLS Passwords' {
                $Logger.LogAutomationStart("Update MXLS Passwords")
                Invoke-UpdateMxlsPasswords -Config $yamlConfig -DebugHelper $DebugHelper
                $Logger.LogAutomationEnd("Update MXLS Passwords", $true)
                $UserInteraction.WriteBlankLine()
                $UserInteraction.WriteActivity("Automation completed. What would you like to do?", 'info')
                $choice = Read-Host "Enter '1' to return to quarterly menu or 'q' to quit"
                $Logger.LogUserInput($choice, "Post-Automation Choice")
                switch ($choice) {
                    '1' {
                        $Logger.LogInfo("User chose to return to quarterly menu", "User Action")
                        $UserInteraction.WriteActivity("Returning to quarterly menu...", 'info')
                        Start-Sleep -Seconds 1
                        continue
                    }
                    'q' {
                        $Logger.LogInfo("User chose to quit application", "User Action")
                        $UserInteraction.WriteActivity("Exiting application...", 'info')
                        Start-Sleep -Seconds 1
                        $Logger.CloseSession()
                        exit
                    }
                    default {
                        $Logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        $UserInteraction.WriteActivity("Invalid choice. Returning to quarterly menu...", 'warning')
                        Start-Sleep -Seconds 2
                        continue
                    }
                }
            }
            'Update Service Account Services' {
                $Logger.LogAutomationStart("Update Service Account Services")
                Invoke-UpdateServiceAccountServices -Config $yamlConfig -DebugHelper $DebugHelper
                $Logger.LogAutomationEnd("Update Service Account Services", $true)
                $UserInteraction.WriteBlankLine()
                $UserInteraction.WriteActivity("Automation completed. What would you like to do?", 'info')
                $choice = Read-Host "Enter '1' to return to quarterly menu or 'q' to quit"
                $Logger.LogUserInput($choice, "Post-Automation Choice")
                switch ($choice) {
                    '1' {
                        $Logger.LogInfo("User chose to return to quarterly menu", "User Action")
                        $UserInteraction.WriteActivity("Returning to quarterly menu...", 'info')
                        Start-Sleep -Seconds 1
                        continue
                    }
                    'q' {
                        $Logger.LogInfo("User chose to quit application", "User Action")
                        $UserInteraction.WriteActivity("Exiting application...", 'info')
                        Start-Sleep -Seconds 1
                        $Logger.CloseSession()
                        exit
                    }
                    default {
                        $Logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        $UserInteraction.WriteActivity("Invalid choice. Returning to quarterly menu...", 'warning')
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
        $ui = [UserInteraction]::GetInstance()
        $logger = [Logger]::GetInstance()
        $automation = $ui.ShowMenu($yamlConfig, 'Audit Requests', @(), $true, $true)
        if ($automation -eq '__BACK__') {
            $logger.LogMenuSelection("Go Back", "Audit Menu")
            return
        }
        if ($automation -eq '__EXIT__') {
            $logger.LogInfo("User chose to exit from audit menu", "User Action")
            $ui.WriteActivity("Exiting application...", 'info')
            Start-Sleep -Seconds 1
            $logger.CloseSession()
            exit
        }
        $ui.WriteActivity("No audit automations configured yet.", 'info')
        Start-Sleep -Seconds 2
        $ui.WriteBlankLine()
        $ui.WriteActivity("What would you like to do?", 'info')
        $choice = Read-Host "Enter '1' to return to audit menu or 'q' to quit"
        $logger.LogUserInput($choice, "Post-Message Choice")
        switch ($choice) {
            '1' {
                $logger.LogInfo("User chose to return to audit menu", "User Action")
                $ui.WriteActivity("Returning to audit menu...", 'info')
                Start-Sleep -Seconds 1
                continue
            }
            'q' {
                $logger.LogInfo("User chose to quit application", "User Action")
                $ui.WriteActivity("Exiting application...", 'info')
                Start-Sleep -Seconds 1
                $logger.CloseSession()
                exit
            }
            default {
                $logger.LogWarning("Invalid choice entered: $choice", "User Input")
                $ui.WriteActivity("Invalid choice. Returning to audit menu...", 'warning')
                Start-Sleep -Seconds 2
                continue
            }
        }
    }
}

function Show-PatchingMenu {
    while ($true) {
        Clear-Host
        $ui = [UserInteraction]::GetInstance()
        $logger = [Logger]::GetInstance()
        $automation = $ui.ShowMenu($yamlConfig, 'Patching Automations', @(), $true, $true)
        if ($automation -eq '__BACK__') {
            $logger.LogMenuSelection("Go Back", "Patching Menu")
            return
        }
        if ($automation -eq '__EXIT__') {
            $logger.LogInfo("User chose to exit from patching menu", "User Action")
            $ui.WriteActivity("Exiting application...", 'info')
            Start-Sleep -Seconds 1
            $logger.CloseSession()
            exit
        }
        $ui.WriteActivity("No patching automations configured yet.", 'info')
        Start-Sleep -Seconds 2
        $ui.WriteBlankLine()
        $ui.WriteActivity("What would you like to do?", 'info')
        $choice = Read-Host "Enter '1' to return to patching menu or 'q' to quit"
        $logger.LogUserInput($choice, "Post-Message Choice")
        switch ($choice) {
            '1' {
                $logger.LogInfo("User chose to return to patching menu", "User Action")
                $ui.WriteActivity("Returning to patching menu...", 'info')
                Start-Sleep -Seconds 1
                continue
            }
            'q' {
                $logger.LogInfo("User chose to quit application", "User Action")
                $ui.WriteActivity("Exiting application...", 'info')
                Start-Sleep -Seconds 1
                $logger.CloseSession()
                exit
            }
            default {
                $logger.LogWarning("Invalid choice entered: $choice", "User Input")
                $ui.WriteActivity("Invalid choice. Returning to patching menu...", 'warning')
                Start-Sleep -Seconds 2
                continue
            }
        }
    }
}

function Show-AdminMenu {
    while ($true) {
        Clear-Host
        $ui = [UserInteraction]::GetInstance()
        $logger = [Logger]::GetInstance()
        $adminOption = $ui.ShowMenu($yamlConfig, 'Administration', @('Start Environment', 'Stop Environment', 'Health Monitor', 'Enable and Disable Task Scheduler Jobs'), $true, $true)
        if ($adminOption -eq '__BACK__') {
            $logger.LogMenuSelection("Go Back", "Admin Menu")
            return
        }
        if ($adminOption -eq '__EXIT__') {
            $logger.LogInfo("User chose to exit from administration menu", "User Action")
            $ui.WriteActivity("Exiting application...", 'info')
            Start-Sleep -Seconds 1
            $logger.CloseSession()
            exit
        }
        switch ($adminOption) {
            'Start Environment' {
                $Logger.LogAutomationStart("Start Environment")
                Invoke-AdminEnvironment -Config $yamlConfig -Mode 'Start' -DebugHelper $DebugHelper
                $Logger.LogAutomationEnd("Start Environment", $true)
                $UserInteraction.WriteBlankLine()
                $UserInteraction.WriteActivity("Automation completed. What would you like to do?", 'info')
                $choice = Read-Host "Enter '1' to return to administration menu or 'q' to quit"
                $Logger.LogUserInput($choice, "Post-Automation Choice")
                switch ($choice) {
                    '1' {
                        $Logger.LogInfo("User chose to return to administration menu", "User Action")
                        $UserInteraction.WriteActivity("Returning to administration menu...", 'info')
                        Start-Sleep -Seconds 1
                        continue
                    }
                    'q' {
                        $Logger.LogInfo("User chose to quit application", "User Action")
                        $UserInteraction.WriteActivity("Exiting application...", 'info')
                        Start-Sleep -Seconds 1
                        $Logger.CloseSession()
                        exit
                    }
                    default {
                        $Logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        $UserInteraction.WriteActivity("Invalid choice. Returning to administration menu...", 'warning')
                        Start-Sleep -Seconds 2
                        continue
                    }
                }
            }
            'Stop Environment' {
                $Logger.LogAutomationStart("Stop Environment")
                Invoke-AdminEnvironment -Config $yamlConfig -Mode 'Stop' -DebugHelper $DebugHelper
                $Logger.LogAutomationEnd("Stop Environment", $true)
                $UserInteraction.WriteBlankLine()
                $UserInteraction.WriteActivity("Automation completed. What would you like to do?", 'info')
                $choice = Read-Host "Enter '1' to return to administration menu or 'q' to quit"
                $Logger.LogUserInput($choice, "Post-Automation Choice")
                switch ($choice) {
                    '1' {
                        $Logger.LogInfo("User chose to return to administration menu", "User Action")
                        $UserInteraction.WriteActivity("Returning to administration menu...", 'info')
                        Start-Sleep -Seconds 1
                        continue
                    }
                    'q' {
                        $Logger.LogInfo("User chose to quit application", "User Action")
                        $UserInteraction.WriteActivity("Exiting application...", 'info')
                        Start-Sleep -Seconds 1
                        $Logger.CloseSession()
                        exit
                    }
                    default {
                        $Logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        $UserInteraction.WriteActivity("Invalid choice. Returning to administration menu...", 'warning')
                        Start-Sleep -Seconds 2
                        continue
                    }
                }
            }
            'Health Monitor' {
                $Logger.LogAutomationStart("Health Monitor")
                $result = Invoke-HealthMonitor -Config $yamlConfig -DebugHelper $DebugHelper
                
                # Health Monitor now handles its own confirmation and returns either '__BACK__' or '__EXIT__'
                if ($result -eq '__BACK__') {
                    # User chose to go back to menu
                    $Logger.LogInfo("User chose to return to administration menu from health monitor", "User Action")
                    continue
                } elseif ($result -eq '__EXIT__') {
                    # User chose to exit application
                    $Logger.LogInfo("User chose to exit application from health monitor", "User Action")
                    $UserInteraction.WriteActivity("Exiting application...", 'info')
                    Start-Sleep -Seconds 1
                    $Logger.CloseSession()
                    exit
                } else {
                    # For any other result, log completion and continue to menu
                    $Logger.LogAutomationEnd("Health Monitor", $result)
                    continue
                }
            }
            'Enable and Disable Task Scheduler Jobs' {
                $Logger.LogAutomationStart("Enable and Disable Task Scheduler Jobs")
                Invoke-EnableDisableTaskSchedulerJobs -Config $yamlConfig -DebugHelper $DebugHelper
                $Logger.LogAutomationEnd("Enable and Disable Task Scheduler Jobs", $true)
                $UserInteraction.WriteBlankLine()
                $UserInteraction.WriteActivity("Automation completed. What would you like to do?", 'info')
                $choice = Read-Host "Enter '1' to return to administration menu or 'q' to quit"
                $Logger.LogUserInput($choice, "Post-Automation Choice")
                switch ($choice) {
                    '1' {
                        $Logger.LogInfo("User chose to return to administration menu", "User Action")
                        $UserInteraction.WriteActivity("Returning to administration menu...", 'info')
                        Start-Sleep -Seconds 1
                        continue
                    }
                    'q' {
                        $Logger.LogInfo("User chose to quit application", "User Action")
                        $UserInteraction.WriteActivity("Exiting application...", 'info')
                        Start-Sleep -Seconds 1
                        $Logger.CloseSession()
                        exit
                    }
                    default {
                        $Logger.LogWarning("Invalid choice entered: $choice", "User Input")
                        $UserInteraction.WriteActivity("Invalid choice. Returning to administration menu...", 'warning')
                        Start-Sleep -Seconds 2
                        continue
                    }
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
    try {
        $logger = [Logger]::GetInstance()
        $logger.CloseSession()
    } catch {
        # Ignore logger cleanup errors during exit
    }
} 