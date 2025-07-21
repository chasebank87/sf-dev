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
                
                $tasks = $debugHelper.InvokeOrDebug($session, {
                    param($serviceAccount)
                    Get-ScheduledTask | Where-Object { $_.Principal.UserId -eq $serviceAccount } | 
                    Select-Object TaskName, TaskPath
                }, "Retrieving scheduled tasks for $serviceAccount", "Get-ScheduledTask", @($serviceAccount))
                
                Write-Activity "Found $($tasks.Count) tasks matching the user ${serviceAccount} on ${serverName}." -type 'info'
                $logger.LogServerOperation($serverName, "Task Retrieval", "Found $($tasks.Count) tasks")
                
                $allResults += [PSCustomObject]@{
                    Server = "$serverName ($serverAddress)"
                    Tasks  = $tasks.TaskName
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
            # Find the session for this server
            $session = $sessions | Where-Object { $_.ComputerName -eq ($serverName -split ' ')[1].Trim('()') }
            if (-not $session) {
                Write-Activity "No session found for ${serverName}, skipping..." -type 'error'
                $logger.LogError("No session found for ${serverName}", "Session Management")
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
                } catch {
                    Write-Activity "Failed to update password for '$task' on ${serverName}: $($_.Exception.Message)" -type 'error'
                    $logger.LogTaskOperation($serverName, $task, "Password Update", $false)
                    $logger.LogError("Failed to update password for '$task' on ${serverName}: $($_.Exception.Message)", "Task Operation")
                    $failureCount++
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