using module core/AutomationScript.psm1
using module core/UserInteraction.psm1
using module core/Logger.psm1
using module core/DebugHelper.psm1
using module core/SessionHelper.psm1

function Show-PostOperationMenu {
    param(
        [object]$yamlConfig,
        [object]$ui,
        [object]$logger
    )
    
    $postOpChoice = $ui.ShowMenu($yamlConfig, "What would you like to do next?", @(
        'Return to Enable/Disable Task Scheduler Jobs menu',
        'Return to Main Menu',
        'Quit Application'
    ), $false, $true)
    
    if ($postOpChoice -eq 'Return to Enable/Disable Task Scheduler Jobs menu') {
        return 'continue'
    } elseif ($postOpChoice -eq 'Return to Main Menu') {
        return 'return'
    } elseif ($postOpChoice -eq 'Quit Application' -or $postOpChoice -eq '__EXIT__') {
        $logger.LogInfo("User chose to quit application", "User Action")
        $ui.WriteActivity("Exiting application...", 'info')
        Start-Sleep -Seconds 1
        $logger.CloseSession()
        exit
    }
    return 'continue'  # Default fallback
}

function Invoke-EnableDisableTaskSchedulerJobs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [object]$DebugHelper
    )
    
    # Session-wide password storage
    $sessionPassword = $null
    $sessionUser = $null
    
    # Function entry logging
    $logger = [Logger]::GetInstance()
    $logger.LogInfo("=== ENABLE/DISABLE TASK SCHEDULER JOBS FUNCTION START ===", "Task Scheduler Jobs")
    $logger.LogInfo("Config loaded: $($Config.servers.Count) servers configured", "Task Scheduler Jobs")
    $logger.LogInfo("Debug mode: $($DebugHelper.IsDebug())", "Task Scheduler Jobs")
    
    # Get UserInteraction instance
    $ui = [UserInteraction]::GetInstance()
    
    # Validate configuration
    $servers = $Config.servers
    $serviceAccount = $Config.service_account
    
    $logger.LogInfo("Configuration validation:", "Task Scheduler Jobs")
    $logger.LogInfo("- Servers count: $($servers.Count)", "Task Scheduler Jobs")
    $logger.LogInfo("- Service account: $serviceAccount", "Task Scheduler Jobs")
    
    # Log server details
    foreach ($server in $servers) {
        $logger.LogInfo("Configured server: $($server.name) ($($server.address))", "Task Scheduler Jobs")
        if ($server.tasks) {
            $logger.LogInfo("  Tasks: $($server.tasks -join ', ')", "Task Scheduler Jobs")
        }
    }
    
    # Main menu loop
    while ($true) {
        # Step 1: Ask user if they want to enable, disable jobs, or provide password
        Clear-Host
        
        $menuOptions = @('Enable Jobs', 'Disable Jobs', "Provide Service Account Password ($($Config.service_account))")
        if ($sessionPassword) {
            $menuOptions += "Clear Session Password (Service Account: $sessionUser)"
        }
        
        $action = $ui.ShowMenu($yamlConfig, 'Enable/Disable Task Scheduler Jobs', $menuOptions, $true, $true)
        
        if ($action -eq '__BACK__') {
            $logger.LogMenuSelection("Go Back", "Task Scheduler Jobs Menu")
            return
        }
        if ($action -eq '__EXIT__') {
            $logger.LogInfo("User chose to exit from task scheduler jobs menu", "User Action")
            $ui.WriteActivity("Exiting application...", 'info')
            Start-Sleep -Seconds 1
            $logger.CloseSession()
            exit
        }
        
        # Handle password management
        if ($action -like 'Provide Service Account Password*') {
            Clear-Host
            $ui.ShowScriptTitle("Provide Session Password")
            $ui.WriteBlankLine()
            
            # Use service account from config
            $sessionUser = $Config.service_account
            $ui.WriteActivity("Setting session password for service account: $sessionUser", 'info')
            $ui.WriteActivity("This password will be used for all task operations in this session.", 'info')
            $ui.WriteBlankLine()
            
            $sessionPassword = $ui.ReadVerifiedPassword("Enter password for $sessionUser")
            $ui.WriteActivity("Session password stored for service account: $sessionUser", 'success')
            $ui.WriteBlankLine()
            $ui.WriteActivity("This password will be used for all task operations until you exit this menu.", 'info')
            Start-Sleep -Seconds 2
            continue
        }
        
        if ($action -like "Clear Session Password*") {
            $sessionPassword.Dispose()
            $sessionPassword = $null
            $sessionUser = $null
            $ui.WriteActivity("Session password cleared.", 'info')
            Start-Sleep -Seconds 1
            continue
        }
        
        $isEnableAction = $action -eq 'Enable Jobs'
        $actionText = if ($isEnableAction) { "Enable" } else { "Disable" }
        $statusFilter = if ($isEnableAction) { "Disabled" } else { "Enabled" }
        
        $logger.LogInfo("User selected: $actionText jobs", "Task Scheduler Jobs")
    
    # Step 2: Collect all tasks from config and service account
    $allTasks = @()
    
    # Add tasks from config
    foreach ($server in $servers) {
        if ($server.tasks) {
            $logger.LogInfo("Processing tasks for server: $($server.name)", "Task Scheduler Jobs")
            foreach ($task in $server.tasks) {
                $logger.LogInfo("Adding config task: $task on $($server.name)", "Task Scheduler Jobs")
                $allTasks += [PSCustomObject]@{
                    ServerName = $server.name
                    ServerAddress = $server.address
                    TaskName = $task
                    Source = "Config"
                }
            }
        } else {
            $logger.LogInfo("No tasks configured for server: $($server.name)", "Task Scheduler Jobs")
        }
    }
    
    # Add tasks running as service account (we'll discover these)
    $logger.LogInfo("Collecting tasks from $($servers.Count) servers", "Task Scheduler Jobs")
    
    foreach ($server in $servers) {
        try {
            $logger.LogInfo("Discovering tasks on server: $($server.name)", "Task Scheduler Jobs")
            
            # Get tasks running as service account
            $cmd = "schtasks /query /s $($server.address) /fo csv /nh"
            $debugHelper.LogCommand($cmd, "Query tasks on $($server.name)")
            
            $tasksOutput = $debugHelper.ExecuteOrDebug({ 
                Invoke-Expression $cmd 
            }, "Query tasks on $($server.name)", "schtasks")
            
            if ($tasksOutput) {
                $tasks = $tasksOutput | ConvertFrom-Csv
                foreach ($task in $tasks) {
                    if ($task.'TaskName' -and $task.'TaskName' -ne 'TaskName') {
                        # Check if task runs as service account
                        $taskDetailsCmd = "schtasks /query /s $($server.address) /tn `"$($task.TaskName)`" /fo csv /nh"
                        $taskDetails = $debugHelper.ExecuteOrDebug({ 
                            Invoke-Expression $taskDetailsCmd 
                        }, "Get task details for $($task.TaskName)", "schtasks")
                        
                        if ($taskDetails) {
                            $taskInfo = $taskDetails | ConvertFrom-Csv
                            if ($taskInfo.'Run As User' -like "*$serviceAccount*") {
                                $allTasks += [PSCustomObject]@{
                                    ServerName = $server.name
                                    ServerAddress = $server.address
                                    TaskName = $task.TaskName
                                    Source = "Service Account"
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            $logger.LogError("Failed to discover tasks on $($server.name): $_", "Task Scheduler Jobs")
            $ui.WriteActivity("Failed to discover tasks on $($server.name): $_", 'error')
        }
    }
    
    $logger.LogInfo("Total tasks collected: $($allTasks.Count)", "Task Scheduler Jobs")
    
    # Log collected tasks for debugging
    foreach ($task in $allTasks) {
        $logger.LogInfo("Collected task: $($task.ServerName) - $($task.TaskName) ($($task.Source))", "Task Scheduler Jobs")
    }
    
    # Step 3: Filter tasks by status and show to user
    $filteredTasks = @()
    
    foreach ($task in $allTasks) {
        try {
                        # Get task status directly
            $statusCmd = "schtasks /query /s $($task.ServerAddress) /tn `"$($task.TaskName)`" /fo csv /nh"
            $logger.LogInfo("Executing command: $statusCmd", "Task Scheduler Jobs")
            
            try {
                $taskStatus = Invoke-Expression $statusCmd
                $logger.LogInfo("Raw task status output for $($task.TaskName): '$taskStatus'", "Task Scheduler Jobs")
                
                if ($taskStatus -and $taskStatus.Trim() -ne "") {
                    try {
                        # Handle potential duplicate entries by splitting on newlines and taking the first valid entry
                        $taskStatusLines = $taskStatus -split "`n" | Where-Object { $_.Trim() -ne "" }
                        
                        if ($taskStatusLines.Count -gt 0) {
                            # Take the first line that contains the task name
                            $firstValidLine = $taskStatusLines | Where-Object { $_ -like "*$($task.TaskName)*" } | Select-Object -First 1
                            
                            if ($firstValidLine) {
                                $logger.LogInfo("Parsing line: $firstValidLine", "Task Scheduler Jobs")
                                
                                # Parse the CSV line manually to handle the format
                                if ($firstValidLine -match '"([^"]+)","([^"]+)","([^"]+)"') {
                                    # $matches[1] = task name, $matches[2] = next run time
                                    $currentStatus = $matches[3]
                                    
                                    $logger.LogInfo("Task $($task.TaskName) status: $currentStatus", "Task Scheduler Jobs")
                                    
                                    # For enabling: look for Disabled tasks
                                    # For disabling: look for Ready tasks (which are enabled and ready to run)
                                    if ($isEnableAction -and $currentStatus -eq "Disabled") {
                                        $logger.LogInfo("Adding $($task.TaskName) to enable list (status: $currentStatus)", "Task Scheduler Jobs")
                                        $filteredTasks += $task
                                    } elseif (-not $isEnableAction -and $currentStatus -eq "Ready") {
                                        $logger.LogInfo("Adding $($task.TaskName) to disable list (status: $currentStatus)", "Task Scheduler Jobs")
                                        $filteredTasks += $task
                                    } else {
                                        $logger.LogInfo("Skipping $($task.TaskName) - status $currentStatus doesn't match filter", "Task Scheduler Jobs")
                                    }
                                } else {
                                    $logger.LogWarning("Failed to parse CSV format for $($task.TaskName): $firstValidLine", "Task Scheduler Jobs")
                                }
                            } else {
                                $logger.LogWarning("No valid line found for task $($task.TaskName)", "Task Scheduler Jobs")
                            }
                        } else {
                            $logger.LogWarning("No valid lines in output for task $($task.TaskName)", "Task Scheduler Jobs")
                        }
                    } catch {
                        $logger.LogWarning("Failed to parse status for $($task.TaskName) on $($task.ServerName): $_", "Task Scheduler Jobs")
                    }
                } else {
                    $logger.LogWarning("No status output for task $($task.TaskName)", "Task Scheduler Jobs")
                }
            } catch {
                $logger.LogWarning("Failed to execute command for $($task.TaskName): $_", "Task Scheduler Jobs")
            }
        } catch {
            $logger.LogWarning("Failed to get status for $($task.TaskName) on $($task.ServerName): $_", "Task Scheduler Jobs")
        }
    }
    
    $logger.LogInfo("Filtered tasks count: $($filteredTasks.Count)", "Task Scheduler Jobs")
    foreach ($task in $filteredTasks) {
        $logger.LogInfo("Filtered task: $($task.ServerName) - $($task.TaskName) ($($task.Source))", "Task Scheduler Jobs")
    }
    
        if ($filteredTasks.Count -eq 0) {
            $ui.WriteActivity("No $statusFilter.ToLower() jobs found.", 'info')
            $ui.WriteBlankLine()
            
            # Post-operation menu for no jobs found
            $menuResult = Show-PostOperationMenu -yamlConfig $yamlConfig -ui $ui -logger $logger
            if ($menuResult -eq 'continue') {
                continue
            } elseif ($menuResult -eq 'return') {
                return
            }
        }
    
    # Step 4: Display filtered tasks to user
    Clear-Host
    
    # Create task list for menu
    $taskList = @()
    for ($i = 0; $i -lt $filteredTasks.Count; $i++) {
        $task = $filteredTasks[$i]
        $taskList += "$($task.ServerName) - $($task.TaskName) ($($task.Source))"
    }
    
    $selection = $ui.ShowMenu($yamlConfig, "$actionText Task Scheduler Jobs", $taskList, $true, $true)
    
    if ($selection -eq '__BACK__') {
        $logger.LogMenuSelection("Go Back", "Task Selection")
        continue
    }
    if ($selection -eq '__EXIT__') {
        $logger.LogInfo("User chose to exit from task selection", "User Action")
        $ui.WriteActivity("Exiting application...", 'info')
        Start-Sleep -Seconds 1
        $logger.CloseSession()
        exit
    }
    
    # Find the selected task
    $selectedTaskIndex = [array]::IndexOf($taskList, $selection)
    $selectedTask = $filteredTasks[$selectedTaskIndex]
    
    # Step 5: Confirm action
    Clear-Host
    $ui.ShowScriptTitle("Confirm $actionText Action")
    $ui.WriteBlankLine()
    $ui.WriteActivity("You are about to $($actionText.ToLower()) the following job:", 'warning')
    $ui.WriteBlankLine()
    
    # Create table data for the job details
    $jobTable = @(
        [PSCustomObject]@{
            'Property' = 'Server'
            'Value' = $selectedTask.ServerName
        },
        [PSCustomObject]@{
            'Property' = 'Task Name'
            'Value' = $selectedTask.TaskName
        },
        [PSCustomObject]@{
            'Property' = 'Source'
            'Value' = $selectedTask.Source
        }
    )
    
    # Display the table using UserInteraction class
    $ui.WriteTable($jobTable, @('Property', 'Value'), @('Property', 'Value'))
    $ui.WriteBlankLine()
    
    $confirm = $ui.ShowMenu($yamlConfig, "Confirm $actionText Action", @('Yes, proceed', 'No, cancel'), $false, $true)
    
    if ($confirm -eq '__BACK__') {
        $logger.LogMenuSelection("Go Back", "Confirmation")
        continue
    }
    if ($confirm -eq '__EXIT__') {
        $logger.LogInfo("User chose to exit from confirmation", "User Action")
        $ui.WriteActivity("Exiting application...", 'info')
        Start-Sleep -Seconds 1
        $logger.CloseSession()
        exit
    }
    
    if ($confirm -ne 'Yes, proceed') {
        $ui.WriteActivity("Operation cancelled by user.", 'info')
        $ui.WriteBlankLine()
        
        # Post-operation menu for cancelled operation
        $menuResult = Show-PostOperationMenu -yamlConfig $yamlConfig -ui $ui -logger $logger
        if ($menuResult -eq 'continue') {
            continue
        } elseif ($menuResult -eq 'return') {
            return
        }
    }
    
    # Step 6: Execute the action
    $logger.LogInfo("Executing $actionText action on $($selectedTask.TaskName) on $($selectedTask.ServerName)", "Task Scheduler Jobs")
    
    try {
        if ($isEnableAction) {
            # Enable the job
            $enableCmd = "schtasks /change /s $($selectedTask.ServerAddress) /tn `"$($selectedTask.TaskName)`" /enable"
            $debugHelper.LogCommand($enableCmd, "Enable task $($selectedTask.TaskName)")
            
            $enableResult = $debugHelper.ExecuteOrDebug({ 
                Invoke-Expression $enableCmd 
            }, "Enable task $($selectedTask.TaskName)", "schtasks")
            
            $logger.LogInfo("Enable command result: $enableResult", "Task Scheduler Jobs")
            
            # Handle Windows Task Scheduler bug: extract, remove, and re-add triggers
            $ui.WriteActivity("Handling Windows Task Scheduler bug...", 'info')
            
            # Get current triggers
            $triggersCmd = "schtasks /query /s $($selectedTask.ServerAddress) /tn `"$($selectedTask.TaskName)`" /xml"
            $debugHelper.LogCommand($triggersCmd, "Get triggers for $($selectedTask.TaskName)")
            
            $xmlOutput = Invoke-Expression $triggersCmd
            
            $logger.LogInfo("XML command result for $($selectedTask.TaskName): '$xmlOutput'", "Task Scheduler Jobs")
            
            if ($xmlOutput -and $xmlOutput.Trim() -ne "") {
                $logger.LogInfo("XML output received for $($selectedTask.TaskName): $xmlOutput", "Task Scheduler Jobs")
                # Parse XML to extract triggers
                try {
                    $xml = [xml]$xmlOutput
                    $logger.LogInfo("XML parsed successfully for $($selectedTask.TaskName)", "Task Scheduler Jobs")
                    
                    # Get all child nodes under Triggers (LogonTrigger, CalendarTrigger, etc.)
                    $triggers = $xml.Task.Triggers.ChildNodes
                    $logger.LogInfo("Triggers found: $($triggers.Count)", "Task Scheduler Jobs")
                    
                    # Log each trigger type found
                    foreach ($trigger in $triggers) {
                        $logger.LogInfo("Found trigger type: $($trigger.LocalName)", "Task Scheduler Jobs")
                    }
                    
                    if ($triggers) {
                        $ui.WriteActivity("Found $($triggers.Count) trigger(s) that will be removed and restored:", 'info')
                        $ui.WriteBlankLine()
                        
                        # Display triggers in table format
                        $triggerTable = @()
                        for ($i = 0; $i -lt $triggers.Count; $i++) {
                            $trigger = $triggers[$i]
                            $triggerInfo = [PSCustomObject]@{
                                '#' = $i + 1
                                'Type' = $trigger.LocalName
                                'Enabled' = if ($null -ne $trigger.Enabled) { $trigger.Enabled } else { "True" }
                                'Start' = if ($trigger.StartBoundary) { $trigger.StartBoundary } else { "N/A" }
                                'End' = if ($trigger.EndBoundary) { $trigger.EndBoundary } else { "N/A" }
                                'Repetition' = if ($trigger.Repetition) { "$($trigger.Repetition.Interval)/$($trigger.Repetition.Duration)" } else { "None" }
                            }
                            $triggerTable += $triggerInfo
                        }
                        
                        $ui.WriteTable($triggerTable, @('#', 'Type', 'Enabled', 'Start', 'End', 'Repetition'), @('#', 'Type', 'Enabled', 'Start', 'End', 'Repetition'))
                        $ui.WriteBlankLine()
                        
                        # Create backup directory if it doesn't exist
                        $backupDir = "$PSScriptRoot/../backups/task_scheduler"
                        if (-not (Test-Path $backupDir)) {
                            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                            $logger.LogInfo("Created backup directory: $backupDir", "Task Scheduler Jobs")
                        }
                        
                        # Create backup file with timestamp
                        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                        $backupPath = "$backupDir/$($selectedTask.TaskName)_$timestamp.xml"
                        $xmlOutput | Out-File -FilePath $backupPath -Encoding Unicode
                        $logger.LogInfo("Created backup of task XML: $backupPath", "Task Scheduler Jobs")
                        
                        # Store the complete XML for re-importing
                        $tempXmlPath = [System.IO.Path]::GetTempFileName() + ".xml"
                        # Use UTF16 encoding to match the original XML encoding
                        $xmlOutput | Out-File -FilePath $tempXmlPath -Encoding Unicode
                        $logger.LogInfo("Saved task XML to temporary file: $tempXmlPath", "Task Scheduler Jobs")
                        
                        # Delete the task (this removes all triggers)
                        $deleteCmd = "schtasks /delete /s $($selectedTask.ServerAddress) /tn `"$($selectedTask.TaskName)`" /f"
                        $debugHelper.LogCommand($deleteCmd, "Delete task $($selectedTask.TaskName)")
                        
                        $deleteResult = $debugHelper.ExecuteOrDebug({ 
                            Invoke-Expression $deleteCmd 
                        }, "Delete task $($selectedTask.TaskName)", "schtasks")
                        
                        $logger.LogInfo("Delete task result: $deleteResult", "Task Scheduler Jobs")
                        # Check if delete was successful by trying to query the task
                        $verifyDeleteCmd = "schtasks /query /s $($selectedTask.ServerAddress) /tn `"$($selectedTask.TaskName)`" 2>&1"
                        $verifyResult = Invoke-Expression $verifyDeleteCmd
                        $deleteSuccess = $verifyResult -like "*ERROR*" -or $verifyResult -like "*cannot find*"
                        $logger.LogInfo("Delete verification result: $verifyResult", "Task Scheduler Jobs")
                        $logger.LogInfo("Delete success: $deleteSuccess", "Task Scheduler Jobs")
                        
                        # Re-create the task from the saved XML (this restores all triggers)
                        # Check if the task runs as a specific user (not SYSTEM) and needs password
                        $xml = [xml]$xmlOutput
                        $principal = $xml.Task.Principals.Principal
                        $needsPassword = $principal.LogonType -eq "Password" -and $principal.UserId -notlike "*SYSTEM*"
                        
                        if ($needsPassword) {
                            $ui.WriteActivity("This task runs as a specific user and requires a password for recreation.", 'warning')
                            $ui.WriteActivity("Original User: $($principal.UserId)", 'info')
                            
                            # Always use the service account from config for consistency
                            $taskUser = $Config.service_account
                            $ui.WriteActivity("Setting task to run as service account: $taskUser", 'info')
                            $ui.WriteBlankLine()
                            
                            # Check if we have a session password for the service account
                            if ($sessionPassword -and $sessionUser -eq $taskUser) {
                                $ui.WriteActivity("Using stored session password for $sessionUser", 'info')
                                $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sessionPassword))
                                $userPassword = $sessionPassword
                            } else {
                                # Prompt for password for the service account
                                $userPassword = $ui.ReadVerifiedPassword("Enter password for service account $taskUser")
                                $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($userPassword))
                            }
                            
                            # Use /f to force creation and include service account credentials
                            $createCmd = "schtasks /create /s $($selectedTask.ServerAddress) /tn `"$($selectedTask.TaskName)`" /xml `"$tempXmlPath`" /ru `"$taskUser`" /rp `"$plainPassword`" /f"
                            $debugHelper.LogCommand($createCmd.Replace($plainPassword, "***PASSWORD***"), "Re-create task $($selectedTask.TaskName)")
                        } else {
                            # Task runs as SYSTEM or doesn't need password
                            $createCmd = "schtasks /create /s $($selectedTask.ServerAddress) /tn `"$($selectedTask.TaskName)`" /xml `"$tempXmlPath`" /f"
                            $debugHelper.LogCommand($createCmd, "Re-create task $($selectedTask.TaskName)")
                        }
                        
                        $createResult = $debugHelper.ExecuteOrDebug({ 
                            Invoke-Expression $createCmd 
                        }, "Re-create task $($selectedTask.TaskName)", "schtasks")
                        
                        # Clear password from memory for security (but keep session password)
                        if ($needsPassword) {
                            $plainPassword = $null
                            if ($userPassword -ne $sessionPassword) {
                                $userPassword.Dispose()
                            }
                        }
                        
                        $logger.LogInfo("Re-create task result: $createResult", "Task Scheduler Jobs")
                        # Check if create was successful by trying to query the task
                        $verifyCreateCmd = "schtasks /query /s $($selectedTask.ServerAddress) /tn `"$($selectedTask.TaskName)`" 2>&1"
                        $verifyCreateResult = Invoke-Expression $verifyCreateCmd
                        $createSuccess = $verifyCreateResult -notlike "*ERROR*" -and $verifyCreateResult -notlike "*cannot find*"
                        $logger.LogInfo("Create verification result: $verifyCreateResult", "Task Scheduler Jobs")
                        $logger.LogInfo("Create success: $createSuccess", "Task Scheduler Jobs")
                        
                        # Clean up temporary file
                        try {
                            Remove-Item -Path $tempXmlPath -Force
                            $logger.LogInfo("Cleaned up temporary XML file", "Task Scheduler Jobs")
                        } catch {
                            $logger.LogWarning("Failed to clean up temporary XML file: $_", "Task Scheduler Jobs")
                        }
                        
                        # Create status table for trigger operations
                        $triggerStatusTable = @(
                            [PSCustomObject]@{
                                'Operation' = 'Task XML Backed Up'
                                'Status' = 'Success'
                                'Details' = Split-Path $backupPath -Leaf
                            },
                            [PSCustomObject]@{
                                'Operation' = 'Task Deleted'
                                'Status' = if ($deleteSuccess) { 'Success' } else { 'Failed' }
                                'Details' = "$($triggers.Count) triggers"
                            },
                            [PSCustomObject]@{
                                'Operation' = 'Task Re-created'
                                'Status' = if ($createSuccess) { 'Success' } else { 'Failed' }
                                'Details' = "$($triggers.Count) triggers restored"
                            }
                        )
                        
                        $ui.WriteTable($triggerStatusTable, @('Operation', 'Status', 'Details'), @('Operation', 'Status', 'Details'))
                        $ui.WriteBlankLine()
                        $ui.WriteActivity("Triggers successfully re-added.", 'success')
                    } else {
                        $ui.WriteActivity("No triggers found for this task.", 'info')
                    }
                } catch {
                    $logger.LogError("Failed to parse XML or handle triggers: $_", "Task Scheduler Jobs")
                    $ui.WriteActivity("Failed to handle triggers: $_", 'error')
                }
            } else {
                $logger.LogWarning("No XML output received for $($selectedTask.TaskName)", "Task Scheduler Jobs")
                $ui.WriteActivity("No XML output received for task triggers.", 'warning')
            }
            
            $ui.WriteActivity("Task successfully enabled with triggers restored.", 'success')
            
        } else {
            # Disable the job
            $disableCmd = "schtasks /change /s $($selectedTask.ServerAddress) /tn `"$($selectedTask.TaskName)`" /disable"
            $debugHelper.LogCommand($disableCmd, "Disable task $($selectedTask.TaskName)")
            
            $disableResult = $debugHelper.ExecuteOrDebug({ 
                Invoke-Expression $disableCmd 
            }, "Disable task $($selectedTask.TaskName)", "schtasks")
            
            $logger.LogInfo("Disable command result: $disableResult", "Task Scheduler Jobs")
            $ui.WriteActivity("Task successfully disabled.", 'success')
        }
        
        $logger.LogInfo("$actionText operation completed successfully for $($selectedTask.TaskName)", "Task Scheduler Jobs")
        
        } catch {
            $logger.LogError("Failed to $actionText.ToLower() task $($selectedTask.TaskName): $_", "Task Scheduler Jobs")
            $ui.WriteActivity("Failed to $actionText.ToLower() task: $_", 'error')
            $ui.WriteBlankLine()
            
            # Post-operation menu for failed operation
            $menuResult = Show-PostOperationMenu -yamlConfig $yamlConfig -ui $ui -logger $logger
            if ($menuResult -eq 'continue') {
                continue
            } elseif ($menuResult -eq 'return') {
                return
            }
        }
    
        $ui.WriteBlankLine()
        $ui.WriteActivity("Operation completed successfully.", 'success')
        $ui.WriteBlankLine()
        
        # Post-operation menu
        $menuResult = Show-PostOperationMenu -yamlConfig $yamlConfig -ui $ui -logger $logger
        if ($menuResult -eq 'continue') {
            continue
        } elseif ($menuResult -eq 'return') {
            return
        }
        
        } # End of main while loop
        
        # Clean up session password when exiting
        if ($sessionPassword) {
            $sessionPassword.Dispose()
            $sessionPassword = $null
            $sessionUser = $null
        }
} 