using module core/AutomationScript.psm1
using module core/UserInteraction.psm1
using module core/Logger.psm1
using module core/DebugHelper.psm1
using module core/SessionHelper.psm1

function Invoke-UpdateTaskPasswords {
    param([object]$Config)
    
    # Initialize components (get fresh references each time to handle debug mode toggles)
    $logger = Get-Logger
    $UserInteraction = Get-UserInteraction
    
    Clear-Host
    [UserInteraction]::ShowScriptTitle("Update Task Passwords")
    [UserInteraction]::WriteBlankLine()
    [UserInteraction]::WriteActivity("Starting Quarterly Password Change process...", 'info')
    
    $logger.LogInfo("Starting Quarterly Password Change process", "Automation")
    
    # Get service account from config
    $serviceAccount = $Config.service_account
    if (-not $serviceAccount) {
        [UserInteraction]::WriteActivity("Service account not configured in config file!", 'error')
        $logger.LogError("Service account not configured", "Configuration")
        return
    }
    
    # Get all server names that have tasks configured
    $serversWithTasks = (Get-SessionHelper).GetServersWithTasks($serviceAccount)
    if ($serversWithTasks.Count -eq 0) {
        [UserInteraction]::WriteActivity("No servers with tasks found in configuration", 'warning')
        $logger.LogWarning("No servers with tasks configured", "Configuration")
        return
    }
    
    $serverNames = $serversWithTasks | ForEach-Object { $_.ServerName }
    $logger.LogInfo("Processing $($serverNames.Count) servers for service account: $serviceAccount", "Automation")
    
    # Create sessions to all servers at once (with built-in retry and error handling)
    [UserInteraction]::WriteActivity("Creating sessions to $($serverNames.Count) servers...", 'info')
    $sessionInfos = (Get-SessionHelper).CreateMultipleSessions([string[]]$serverNames, $true)
    
    if ($sessionInfos.Count -eq 0) {
        [UserInteraction]::WriteActivity("Failed to create any sessions. Cannot proceed.", 'error')
        $logger.LogError("No sessions could be created", "Session Management")
        return
    }
    
    # Retrieve scheduled tasks from all servers
    [UserInteraction]::WriteActivity("Retrieving scheduled tasks from all servers...", 'info')
    $allResults = Get-TasksFromAllServers -SessionInfos $sessionInfos -ServiceAccount $serviceAccount -SessionHelper (Get-SessionHelper)
    
    # Display results table
    Display-TaskSummary -Results $allResults -UserInteraction $UserInteraction -Logger $logger
    
    # Check if user wants to proceed
    if (-not (Confirm-PasswordUpdate -Results $allResults -Logger $logger -UserInteraction $UserInteraction)) {
        return
    }
    
    # Get new password
    $newPassword = $UserInteraction.ReadVerifiedPassword("Enter the new password for the service account")
    $logger.LogUserInput("[PASSWORD ENTERED]", "New Password Input")
    
    # Update passwords on all servers
    Update-TaskPasswordsOnAllServers -SessionInfos $sessionInfos -Results $allResults -ServiceAccount $serviceAccount -NewPassword $newPassword -SessionHelper (Get-SessionHelper) -UserInteraction $UserInteraction -Logger $logger
    
    # SessionHelper will automatically cleanup sessions when the application exits
    $logger.LogInfo("Task password update process completed", "Automation")
}

function Get-TasksFromAllServers {
    param(
        [object[]]$SessionInfos,
        [string]$ServiceAccount,
        [object]$SessionHelper
    )
    
    $allResults = @()
    
    # Script block to get scheduled tasks
    $getTasksScript = {
        param($serviceAccount)
        
        # Get tasks that currently use the service account
        $dynamicTasks = Get-ScheduledTask | Where-Object { $_.Principal.UserId -eq $serviceAccount } |
            Select-Object TaskName, TaskPath
        
        # Get all tasks for validation
        $allTasks = Get-ScheduledTask | Select-Object TaskName, TaskPath
        
        return @{
            DynamicTasks = $dynamicTasks
            AllTasks = $allTasks
        }
    }
    
    # Execute on all sessions simultaneously
    $results = $sessionHelper.ExecuteOnMultipleSessions($SessionInfos, $getTasksScript, "Retrieve scheduled tasks", @($ServiceAccount))
    
    # Process results
    foreach ($sessionInfo in $SessionInfos) {
        $serverName = $sessionInfo.ServerName
        $serverInfo = $sessionInfo.ServerInfo
        $result = $results[$serverName]
        
        if ($result.Success) {
            $taskData = $result.Result
            $dynamicTasks = $taskData.DynamicTasks
            $allTasks = $taskData.AllTasks
            
            # Combine dynamic tasks with expected tasks from config
            $combinedTasks = @()
            $missingExpectedTasks = @()
            
            # Add dynamic tasks
            if ($dynamicTasks) {
                $combinedTasks += $dynamicTasks.TaskName
                [UserInteraction]::WriteActivity("Found $($dynamicTasks.Count) dynamic tasks matching $ServiceAccount on $serverName", 'info')
            }
            
            # Check expected tasks from configuration
            if ($serverInfo.Tasks -and $serverInfo.Tasks.Count -gt 0) {
                [UserInteraction]::WriteActivity("Checking $($serverInfo.Tasks.Count) expected tasks for $serverName...", 'info')
                foreach ($expectedTask in $serverInfo.Tasks) {
                    $taskExists = $allTasks | Where-Object { $_.TaskName -eq $expectedTask }
                    if ($taskExists) {
                        $isDynamic = $dynamicTasks | Where-Object { $_.TaskName -eq $expectedTask }
                        if ($isDynamic) {
                            if ($expectedTask -notin $combinedTasks) {
                                $combinedTasks += $expectedTask
                            }
                        } else {
                            $combinedTasks += $expectedTask
                            [UserInteraction]::WriteActivity("Expected task '$expectedTask' exists on $serverName but not using service account. Will update.", 'warning')
                        }
                    } else {
                        $missingExpectedTasks += $expectedTask
                        [UserInteraction]::WriteActivity("Expected task '$expectedTask' not found on $serverName", 'warning')
                    }
                }
            } else {
                [UserInteraction]::WriteActivity("No expected tasks configured for $serverName", 'info')
            }
            
            if ($combinedTasks.Count -eq 0) {
                [UserInteraction]::WriteActivity("No tasks found for $ServiceAccount on $serverName", 'warning')
                $allResults += [PSCustomObject]@{
                    Server = "$serverName ($($serverInfo.Address))"
                    Tasks = @()
                    MissingExpected = $missingExpectedTasks
                }
            } else {
                [UserInteraction]::WriteActivity("Found $($combinedTasks.Count) total tasks for $ServiceAccount on $serverName", 'info')
                $allResults += [PSCustomObject]@{
                    Server = "$serverName ($($serverInfo.Address))"
                    Tasks = $combinedTasks
                    MissingExpected = $missingExpectedTasks
                }
            }
        } else {
            [UserInteraction]::WriteActivity("Error retrieving tasks from $serverName`: $($result.Error)", 'error')
            $allResults += [PSCustomObject]@{
                Server = "$serverName ($($serverInfo.Address))"
                Tasks = @("[ERROR: $($result.Error)]")
                MissingExpected = @()
            }
        }
    }
    
    return $allResults
}

function Display-TaskSummary {
    param(
        [object[]]$Results,
        [object]$UserInteraction,
        [object]$Logger
    )
    
    [UserInteraction]::WriteBlankLine()
    $UserInteraction.WriteTable($Results, @('Server','Tasks'), @('Server','Tasks'), @())
    $Logger.LogInfo("Displayed task summary table with $($Results.Count) servers", "Automation")
    
    # Show missing expected tasks
    $serversWithMissingTasks = $Results | Where-Object { $_.MissingExpected -and $_.MissingExpected.Count -gt 0 }
    if ($serversWithMissingTasks.Count -gt 0) {
        [UserInteraction]::WriteBlankLine()
        [UserInteraction]::WriteActivity("The following expected tasks were not found on some servers:", 'warning')
        $Logger.LogWarning("$($serversWithMissingTasks.Count) servers have missing expected tasks", "Task Discovery")
        
        foreach ($result in $serversWithMissingTasks) {
            Write-Host "  Server: $($result.Server)" -ForegroundColor Yellow
            foreach ($missingTask in $result.MissingExpected) {
                Write-Host "    - Missing: $missingTask" -ForegroundColor Red
                $Logger.LogTaskOperation($result.Server, $missingTask, "Missing Expected Task", $false)
            }
            Write-Host ""
        }
    }
}

function Confirm-PasswordUpdate {
    param(
        [object[]]$Results,
        [object]$Logger,
        [object]$UserInteraction
    )
    
    # Calculate total tasks
    $totalTasks = ($Results | ForEach-Object { if ($_.Tasks) { $_.Tasks.Count } else { 0 } } | Measure-Object -Sum).Sum
    if ($totalTasks -eq 0) { $totalTasks = 1 }
    
    $confirm = $UserInteraction.PromptUserForConfirmation("Do you want to proceed with updating passwords for these tasks? (y/n)")
    $Logger.LogUserInput($confirm, "Password Update Confirmation")
    
    if ($confirm -ne 'y') {
        [UserInteraction]::WriteActivity("Operation cancelled by user.", 'warning')
        $Logger.LogWarning("Password update operation cancelled by user", "User Action")
        return $false
    }
    
    return $true
}

function Update-TaskPasswordsOnAllServers {
    param(
        [object[]]$SessionInfos,
        [object[]]$Results,
        [string]$ServiceAccount,
        [System.Security.SecureString]$NewPassword,
        [object]$SessionHelper,
        [object]$UserInteraction,
        [object]$Logger
    )
    
    # Calculate total tasks for progress bar
    $totalTasks = ($Results | ForEach-Object { if ($_.Tasks) { $_.Tasks.Count } else { 0 } } | Measure-Object -Sum).Sum
    if ($totalTasks -eq 0) { $totalTasks = 1 }
    
    $progressBar = $UserInteraction.InitializeProgressBar($totalTasks, "Updating scheduled task passwords")
    
    $successCount = 0
    $failureCount = 0
    $notFoundTasks = @()
    
    # Create session lookup for faster access
    $sessionLookup = @{}
    foreach ($sessionInfo in $SessionInfos) {
        $sessionLookup[$sessionInfo.ServerInfo.Address] = $sessionInfo
    }
    
    foreach ($result in $Results) {
        $serverName = $result.Server
        $tasks = $result.Tasks
        
        # Extract server address from server name
        $serverAddress = ""
        if ($serverName -match '\((.*?)\)') {
            $serverAddress = $matches[1]
        }
        
        $sessionInfo = $sessionLookup[$serverAddress]
        if (-not $sessionInfo) {
            [UserInteraction]::WriteActivity("No session found for $serverName, skipping...", 'error')
            $Logger.LogError("No session found for $serverName", "Session Management")
            continue
        }
        
        if (-not $tasks -or $tasks.Count -eq 0) {
            [UserInteraction]::WriteActivity("No tasks to update for $serverName, skipping...", 'info')
            continue
        }
        
        foreach ($task in $tasks) {
            if ($task -match '^\[ERROR:') { continue }
            
            # Validate task exists and update password
            $updateResult = Update-SingleTaskPassword -SessionInfo $sessionInfo -TaskName $task -ServiceAccount $ServiceAccount -NewPassword $NewPassword -SessionHelper $SessionHelper -Logger $Logger
            
            if ($updateResult.Success) {
                [UserInteraction]::WriteActivity("Successfully updated password for '$task' on $serverName", 'info')
                $successCount++
            } elseif ($updateResult.NotFound) {
                $notFoundTasks += [PSCustomObject]@{ Server = $serverName; Task = $task }
                $Logger.LogTaskOperation($serverName, $task, "Task Not Found", $false)
            } else {
                [UserInteraction]::WriteActivity("Failed to update password for '$task' on $serverName`: $($updateResult.Error)", 'error')
                $failureCount++
            }
            
            $UserInteraction.UpdateProgressBar($progressBar, 1, "$serverName - $task")
        }
    }
    
    # Show summary of not found tasks
    if ($notFoundTasks.Count -gt 0) {
        [UserInteraction]::WriteBlankLine()
        [UserInteraction]::WriteActivity("The following tasks were not found and were skipped:", 'warning')
        $Logger.LogWarning("$($notFoundTasks.Count) tasks were not found and skipped", "Task Operation")
        foreach ($nf in $notFoundTasks) {
            Write-Host "  - $($nf.Task) on $($nf.Server)" -ForegroundColor Yellow
            $Logger.LogTaskOperation($nf.Server, $nf.Task, "Task Not Found", $false)
        }
    }
    
    $UserInteraction.CompleteProgressBar($progressBar)
    $Logger.LogInfo("Password update operation completed. Success: $successCount, Failures: $failureCount, Skipped: $($notFoundTasks.Count)", "Automation")
}

function Update-SingleTaskPassword {
    param(
        [object]$SessionInfo,
        [string]$TaskName,
        [string]$ServiceAccount,
        [System.Security.SecureString]$NewPassword,
        [object]$SessionHelper,
        [object]$Logger
    )
    
    $session = $SessionInfo.Session
    $serverName = $SessionInfo.ServerName
    
    try {
        # First, validate the task exists
        $taskExistsScript = {
            param($taskName)
            try {
                $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
                return Test-Path $task.TaskPath
            } catch {
                return $false
            }
        }
        
        $exists = $sessionHelper.ExecuteOnSession($session, $taskExistsScript, "Checking if task $TaskName exists on $serverName", @($TaskName))
        
        if (-not $exists) {
            return @{ Success = $false; NotFound = $true; Error = "Task not found" }
        }
        
        # Update the task password
        $updatePasswordScript = {
            param($taskName, $user, $securePassword)
            $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
            )
            Set-ScheduledTask -TaskName $taskName -User $user -Password $plainPassword
            Enable-ScheduledTask -TaskName $taskName
        }
        
        $sessionHelper.ExecuteOnSession($session, $updatePasswordScript, "Updating password for task $TaskName on $serverName", @($TaskName, $ServiceAccount, $NewPassword))
        
        $Logger.LogTaskOperation($serverName, $TaskName, "Password Update", $true)
        return @{ Success = $true; NotFound = $false; Error = $null }
        
    } catch {
        $Logger.LogTaskOperation($serverName, $TaskName, "Password Update", $false)
        $Logger.LogError("Failed to update password for '$TaskName' on $serverName`: $($_.Exception.Message)", "Task Operation")
        return @{ Success = $false; NotFound = $false; Error = $_.Exception.Message }
    }
} 