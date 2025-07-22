using module ..\core\AutomationScript.psm1
using module ..\core\UserInteraction.psm1
using module ..\core\Logger.psm1
using module ..\core\DebugHelper.psm1


class UpdateTaskPasswords : AutomationScript {
    UpdateTaskPasswords([object]$config) : base($config) {}
    [void]Run() {
        $logger = Get-Logger
        $debugHelper = Get-DebugHelper
        
        Write-BlankLine
        Write-Activity "Starting Quarterly Password Change process..." -type 'info'
        $logger.LogInfo("Starting Quarterly Password Change process", "Automation")
        
        $servers = $this.Config.servers
        $serviceAccount = $this.Config.service_account
        $logger.LogInfo("Processing $($servers.Count) servers for service account: $serviceAccount", "Automation")
        
        $allResults = @()
        $sessions = @()
        foreach ($server in $servers) {
            $serverName = $server.name
            $serverAddress = $server.address
            Write-Activity "Creating session to ${serverName} (${serverAddress})..." -type 'info'
            $logger.LogServerOperation($serverName, "Session Creation", "Attempting to create PowerShell session")
            
            try {
                $session = $debugHelper.NewPSSessionOrDebug($serverAddress, "Creating session to $serverName")
                $sessions += $session
                $logger.LogServerOperation($serverName, "Session Creation", "SUCCESS")
                
                Write-Activity "Connecting to ${serverName} (${serverAddress}) to retrieve tasks..." -type 'info'
                $logger.LogServerOperation($serverName, "Task Retrieval", "Querying scheduled tasks")
                
                # Get dynamically discovered tasks
                $dynamicTasks = $debugHelper.InvokeOrDebug($session, {
                    param($serviceAccount)
                    Get-ScheduledTask | Where-Object { $_.Principal.UserId -eq $serviceAccount } | 
                    Select-Object TaskName, TaskPath
                }, "Retrieving scheduled tasks for $serviceAccount", "Get-ScheduledTask", @($serviceAccount))
                
                # Get all tasks on the server to check for expected tasks
                $allServerTasks = $debugHelper.InvokeOrDebug($session, {
                    Get-ScheduledTask | Select-Object TaskName, TaskPath
                }, "Retrieving all scheduled tasks", "Get-ScheduledTask", @())
                
                # Combine dynamic and expected tasks
                $combinedTasks = @()
                $missingExpectedTasks = @()
                
                # Add dynamically discovered tasks
                if ($dynamicTasks -and $dynamicTasks.Count -gt 0) {
                    $combinedTasks += $dynamicTasks.TaskName
                    Write-Activity "Found $($dynamicTasks.Count) dynamic tasks matching the user ${serviceAccount} on ${serverName}." -type 'info'
                }
                
                # Check for expected tasks that might not be discovered dynamically
                $serverExpectedTasks = $server.tasks
                if ($serverExpectedTasks -and $serverExpectedTasks.Count -gt 0) {
                    Write-Activity "Checking $($serverExpectedTasks.Count) expected tasks for ${serverName}..." -type 'info'
                    foreach ($expectedTask in $serverExpectedTasks) {
                        # Check if this expected task exists on the server
                        $taskExists = $allServerTasks | Where-Object { $_.TaskName -eq $expectedTask }
                        if ($taskExists) {
                            # Add to combined list if not already included
                            if ($expectedTask -notin $combinedTasks) {
                                $combinedTasks += $expectedTask
                                Write-Activity "Added expected task '$expectedTask' to update list for ${serverName}." -type 'info'
                                $logger.LogServerOperation($serverName, "Task Discovery", "Added expected task: $expectedTask")
                            }
                        } else {
                            $missingExpectedTasks += $expectedTask
                            Write-Activity "Expected task '$expectedTask' not found on ${serverName}." -type 'warning'
                            $logger.LogServerOperation($serverName, "Task Discovery", "Missing expected task: $expectedTask")
                        }
                    }
                } else {
                    Write-Activity "No expected tasks configured for ${serverName}." -type 'info'
                }
                
                # Handle results
                if ($combinedTasks.Count -eq 0) {
                    Write-Activity "No tasks found for ${serviceAccount} on ${serverName}." -type 'warning'
                    $logger.LogServerOperation($serverName, "Task Retrieval", "No tasks found")
                    
                    $allResults += [PSCustomObject]@{
                        Server = "$serverName ($serverAddress)"
                        Tasks  = @()
                        MissingExpected = $missingExpectedTasks
                    }
                } else {
                    Write-Activity "Found $($combinedTasks.Count) total tasks for ${serviceAccount} on ${serverName}." -type 'info'
                    $logger.LogServerOperation($serverName, "Task Retrieval", "Found $($combinedTasks.Count) total tasks")
                    
                    $allResults += [PSCustomObject]@{
                        Server = "$serverName ($serverAddress)"
                        Tasks  = $combinedTasks
                        MissingExpected = $missingExpectedTasks
                    }
                }
            } catch {
                Write-Activity "Error retrieving tasks from ${serverName}: $($_.Exception.Message)" -type 'error'
                $logger.LogError("Error retrieving tasks from ${serverName}: $($_.Exception.Message)", "Server Operation")
                $allResults += [PSCustomObject]@{
                    Server = "$serverName ($serverAddress)"
                    Tasks  = @("[ERROR: $($_.Exception.Message)]")
                }
            }
        }

        Write-BlankLine
        # Print formatted table using Write-Table
        Write-Table -Data $allResults -Columns @('Server','Tasks') -Headers @('Server','Tasks')
        $logger.LogInfo("Displayed task summary table with $($allResults.Count) servers", "Automation")
        
        # Report missing expected tasks
        $serversWithMissingTasks = $allResults | Where-Object { $_.MissingExpected -and $_.MissingExpected.Count -gt 0 }
        if ($serversWithMissingTasks.Count -gt 0) {
            Write-BlankLine
            Write-Activity "⚠️  WARNING: The following expected tasks were not found on some servers:" -type 'warning'
            $logger.LogWarning("$($serversWithMissingTasks.Count) servers have missing expected tasks", "Task Discovery")
            
            foreach ($result in $serversWithMissingTasks) {
                Write-Host "  Server: $($result.Server)" -ForegroundColor Yellow
                foreach ($missingTask in $result.MissingExpected) {
                    Write-Host "    - Missing: $missingTask" -ForegroundColor Red
                    $logger.LogTaskOperation($result.Server, $missingTask, "Missing Expected Task", $false)
                }
                Write-Host ""
            }
        }

        # Calculate total number of tasks for progress bar
        $totalTasks = 0
        foreach ($result in $allResults) {
            if ($result.Tasks) { $totalTasks += $result.Tasks.Count }
        }
        if ($totalTasks -eq 0) { $totalTasks = 1 } # Prevent divide by zero
        $progressBar = Initialize-ProgressBar -TotalTasks $totalTasks -Description "Updating scheduled task passwords"

        $confirm = Read-Host "Do you want to proceed with updating passwords for these tasks? (y/n)"
        $logger.LogUserInput($confirm, "Password Update Confirmation")
        
        if ($confirm -ne 'y') {
            Write-Activity "Operation cancelled by user." -type 'warning'
            $logger.LogWarning("Password update operation cancelled by user", "User Action")
            # Clean up sessions
            if ($sessions.Count -gt 0) { 
                foreach ($session in $sessions) {
                    Remove-PSSession -Session $session
                }
            }
            return
        }

        # Prompt for the new password using Read-VerifiedPassword
        $newPassword = Read-VerifiedPassword -Prompt "Enter the new password for the service account"
        $logger.LogUserInput("[PASSWORD ENTERED]", "New Password Input")

        $notFoundTasks = @()
        $successCount = 0
        $failureCount = 0
        
        foreach ($result in $allResults) {
            $serverName = $result.Server
            $tasks = $result.Tasks
            
            # Extract server address from server name (format: "name (address)")
            $serverAddress = ""
            if ($serverName -match '\((.*?)\)') {
                $serverAddress = $matches[1]
            } else {
                # Fallback: try to extract from the original server list
                $originalServer = $this.Config.servers | Where-Object { "$($_.name) ($($_.address))" -eq $serverName }
                if ($originalServer) {
                    $serverAddress = $originalServer.address
                }
            }
            
            # Find the session for this server
            $session = $sessions | Where-Object { $_.ComputerName -eq $serverAddress }
            if (-not $session) {
                Write-Activity "No session found for ${serverName} (address: ${serverAddress}), skipping..." -type 'error'
                $logger.LogError("No session found for ${serverName} (address: ${serverAddress})", "Session Management")
                continue
            }
            # Skip if no tasks found for this server
            if (-not $tasks -or $tasks.Count -eq 0) {
                Write-Activity "No tasks to update for ${serverName}, skipping..." -type 'info'
                $logger.LogInfo("No tasks to update for ${serverName}", "Task Operation")
                continue
            }
            
            foreach ($task in $tasks) {
                if ($task -match '^\[ERROR:') { continue }
                
                $logger.LogTaskOperation($serverName, $task, "Path Validation", $true)
                
                # Check if the task path exists on the remote server
                $exists = $debugHelper.InvokeOrDebug($session, {
                    param($taskName)
                    try {
                        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
                        Test-Path $task.TaskPath
                    } catch {
                        return $false
                    }
                }, "Checking if task path exists", "Get-ScheduledTask", @($task))

                if (-not $exists) {
                    $notFoundTasks += [PSCustomObject]@{ 
                        Server = $serverName; 
                        Task = $task
                    }
                    $logger.LogTaskOperation($serverName, $task, "Path Validation", $false)
                    
                    # Update progress bar for skipped tasks
                    Update-ProgressBar -ProgressBar $progressBar -CurrentTask "$serverName - $task (SKIPPED)"
                    continue
                }

                Write-Activity "Updating password for task '$task' on ${serverName}..." -type 'info'
                $logger.LogTaskOperation($serverName, $task, "Password Update", $true)
                
                try {
                    $debugHelper.InvokeOrDebug($session, {
                        param($taskName, $user, $securePassword)
                        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
                            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
                        )
                        Set-ScheduledTask -TaskName $taskName -User $user -Password $plainPassword
                        Enable-ScheduledTask -TaskName $taskName
                    }, "Updating password for task $task", "Set-ScheduledTask", @($task, $serviceAccount, $newPassword))
                    
                    Write-Activity "Successfully updated password for '$task' on ${serverName}." -type 'info'
                    $logger.LogTaskOperation($serverName, $task, "Password Update", $true)
                    $successCount++
                    
                    # Update progress bar
                    Update-ProgressBar -ProgressBar $progressBar -CurrentTask "$serverName - $task"
                } catch {
                    Write-Activity "Failed to update password for '$task' on ${serverName}: $($_.Exception.Message)" -type 'error'
                    $logger.LogTaskOperation($serverName, $task, "Password Update", $false)
                    $logger.LogError("Failed to update password for '$task' on ${serverName}: $($_.Exception.Message)", "Task Operation")
                    $failureCount++
                    
                    # Update progress bar even for failures
                    Update-ProgressBar -ProgressBar $progressBar -CurrentTask "$serverName - $task (FAILED)"
                }
            }
        }

        # Report not found tasks
        if ($notFoundTasks.Count -gt 0) {
            Write-BlankLine
            Write-Activity "The following tasks were not found and were skipped:" -type 'warning'
            $logger.LogWarning("$($notFoundTasks.Count) tasks were not found and skipped", "Task Operation")
            foreach ($nf in $notFoundTasks) {
                Write-Host "  - $($nf.Task) on $($nf.Server)" -ForegroundColor Yellow
                $logger.LogTaskOperation($nf.Server, $nf.Task, "Task Not Found", $false)
            }
        }

        # Complete progress bar
        Complete-ProgressBar -ProgressBar $progressBar
        
        # Log final summary
        $logger.LogInfo("Password update operation completed. Success: $successCount, Failures: $failureCount, Skipped: $($notFoundTasks.Count)", "Automation")

        # Clean up sessions
        if ($sessions.Count -gt 0) { 
            foreach ($session in $sessions) {
                Remove-PSSession -Session $session
            }
        }
        $logger.LogInfo("Cleaned up $($sessions.Count) PowerShell sessions", "Session Management")
    }
} 