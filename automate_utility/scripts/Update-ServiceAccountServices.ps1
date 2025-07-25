using module core/AutomationScript.psm1
using module core/UserInteraction.psm1
using module core/Logger.psm1
using module core/DebugHelper.psm1
using module core/SessionHelper.psm1

function Invoke-UpdateServiceAccountServices {
    param([object]$Config)
    $logger = Get-Logger
    $UserInteraction = Get-UserInteraction
    Clear-Host
    [UserInteraction]::ShowScriptTitle("Update Service Account Services")
    [UserInteraction]::WriteBlankLine()
    [UserInteraction]::WriteActivity("Starting Service Account Service Password Change process...", 'info')
    $logger.LogInfo("Starting Service Account Service Password Change process", "Automation")

    $serviceAccount = $Config.service_account
    if (-not $serviceAccount) {
        [UserInteraction]::WriteActivity("Service account not configured in config file!", 'error')
        $logger.LogError("Service account not configured", "Configuration")
        return
    }

    $serverNames = (Get-SessionHelper).GetAllServerNames()
    if ($serverNames.Count -eq 0) {
        [UserInteraction]::WriteActivity("No servers found in configuration", 'warning')
        $logger.LogWarning("No servers found in configuration", "Configuration")
        return
    }

    [UserInteraction]::WriteActivity("Creating sessions to $($serverNames.Count) servers...", 'info')
    $sessionInfos = (Get-SessionHelper).CreateMultipleSessions([string[]]$serverNames, $true)
    if ($sessionInfos.Count -eq 0) {
        [UserInteraction]::WriteActivity("Failed to create any sessions. Cannot proceed.", 'error')
        $logger.LogError("No sessions could be created", "Session Management")
        return
    }

    [UserInteraction]::WriteActivity("Retrieving services running as $serviceAccount from all servers...", 'info')
    try {
        $allResults = Get-ServicesFromAllServers -SessionInfos $sessionInfos -ServiceAccount $serviceAccount -SessionHelper (Get-SessionHelper)
        $logger.LogInfo("Successfully retrieved results from Get-ServicesFromAllServers. Result count: $($allResults.Count)", "Debug")
        
        $logger.LogInfo("About to call Display-ServiceSummary", "Debug")
        Display-ServiceSummary -Results $allResults -UserInteraction $UserInteraction -Logger $logger
        $logger.LogInfo("Display-ServiceSummary completed successfully", "Debug")

        $logger.LogInfo("About to call Confirm-ServicePasswordUpdate", "Debug")
        $confirmResult = Confirm-ServicePasswordUpdate -Results $allResults -Logger $logger -UserInteraction $UserInteraction
        $logger.LogInfo("Confirm-ServicePasswordUpdate returned: $confirmResult", "Debug")
        
        if (-not $confirmResult) {
            $logger.LogInfo("User chose not to proceed with password update", "Debug")
            return
        }
    } catch {
        $logger.LogError("Error in main process flow: $($_.Exception.Message)", "Debug")
        $logger.LogError("Stack trace: $($_.ScriptStackTrace)", "Debug")
        throw
    }

    $newPassword = $UserInteraction.ReadVerifiedPassword("Enter the new password for the service account")
    $logger.LogUserInput("[PASSWORD ENTERED]", "New Password Input")

    Update-ServicePasswordsOnAllServers -SessionInfos $sessionInfos -Results $allResults -ServiceAccount $serviceAccount -NewPassword $newPassword -SessionHelper (Get-SessionHelper) -UserInteraction $UserInteraction -Logger $logger

    $logger.LogInfo("Service password update process completed", "Automation")
}

function Get-ServicesFromAllServers {
    param(
        [object[]]$SessionInfos,
        [string]$ServiceAccount,
        [object]$SessionHelper
    )
    $allResults = @()
    $getServicesScript = {
        param($serviceAccount)
        
        # Create a debug log that will be returned with results
        $debugLog = @()
        $debugLog += "Searching for service account: '$serviceAccount' on $env:COMPUTERNAME"
        
        # Helper function to normalize service account names for comparison
        function Compare-ServiceAccount {
            param($storedName, $searchAccount)
            
            if (-not $storedName -or -not $searchAccount) { return $false }
            
            # Convert both to lowercase for comparison
            $storedName = $storedName.ToLower()
            $searchAccount = $searchAccount.ToLower()
            
            # Direct match
            if ($storedName -eq $searchAccount) { 
                return $true 
            }
            
            # Extract username from different formats
            $storedUser = $storedName
            $searchUser = $searchAccount
            
            # Handle domain\username format
            if ($storedName -match '^(.+)\\(.+)$') { $storedUser = $matches[2] }
            if ($searchAccount -match '^(.+)\\(.+)$') { $searchUser = $matches[2] }
            
            # Handle username@domain format  
            if ($storedName -match '^(.+)@(.+)$') { $storedUser = $matches[1] }
            if ($searchAccount -match '^(.+)@(.+)$') { $searchUser = $matches[1] }
            
            # Compare just the usernames
            if ($storedUser -eq $searchUser) {
                return $true
            }
            
            return $false
        }
        
        try {
            # Use Get-CimInstance to get service information
            $foundServices = @()
            $allServices = Get-CimInstance -ClassName Win32_Service
            $debugLog += "Found $($allServices.Count) total services"
            
            $matchCount = 0
            $checkedCount = 0
            $allServices | ForEach-Object {
                $serviceName = $_.Name
                $startName = $_.StartName
                $checkedCount++
                
                # Only log first 5 services to avoid spam
                if ($checkedCount -le 5) {
                    $debugLog += "Checking service '$serviceName' with StartName '$startName'"
                }
                
                if (Compare-ServiceAccount -storedName $startName -searchAccount $serviceAccount) {
                    $matchCount++
                    $debugLog += "MATCH #${matchCount}: Adding service '$serviceName' (StartName: '$startName')"
                    $foundServices += [PSCustomObject]@{
                        Name = $_.Name
                        DisplayName = $_.DisplayName
                        StartName = $_.StartName
                        State = $_.State
                    }
                }
            }
            
            $debugLog += "Found $($foundServices.Count) matching services"
            
            # Return both the services and debug info
            return [PSCustomObject]@{
                Services = $foundServices
                DebugLog = $debugLog
                Success = $true
                Error = $null
            }
        } catch {
            return [PSCustomObject]@{
                Services = @()
                DebugLog = $debugLog + @("ERROR: $($_.Exception.Message)")
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
    $results = $SessionHelper.ExecuteOnMultipleSessions($SessionInfos, $getServicesScript, "Retrieve services running as $ServiceAccount", @($ServiceAccount))
    foreach ($sessionInfo in $SessionInfos) {
        $serverName = $sessionInfo.ServerName
        $serverInfo = $sessionInfo.ServerInfo
        $result = $results[$serverName]
        if ($result.Success) {
            $scriptResult = $result.Result
            
            # Log debug information
            if ($scriptResult.DebugLog) {
                $logger.LogInfo("=== DEBUG INFO for $serverName ===", "Service Discovery")
                foreach ($debugLine in $scriptResult.DebugLog) {
                    $logger.LogInfo("  $debugLine", "Service Discovery")
                }
                $logger.LogInfo("=== END DEBUG INFO for $serverName ===", "Service Discovery")
            }
            
            $services = $scriptResult.Services
            $allResults += [PSCustomObject]@{
                Server = "$serverName ($($serverInfo.Address))"
                Services = $services
            }
        } else {
            $logger.LogError("Failed to retrieve services from $serverName`: $($result.Error)", "Service Discovery")
            $allResults += [PSCustomObject]@{
                Server = "$serverName ($($serverInfo.Address))"
                Services = @([PSCustomObject]@{ Name = "[ERROR: $($result.Error)]"; DisplayName = ""; StartName = ""; State = "" })
            }
        }
    }
    return $allResults
}

function Display-ServiceSummary {
    param(
        [object[]]$Results,
        [object]$UserInteraction,
        [object]$Logger
    )
    $Logger.LogInfo("Display-ServiceSummary started. Results count: $($Results.Count)", "Debug")
    
    [UserInteraction]::WriteBlankLine()
    $totalServices = 0
    $serverCount = 0
    
    foreach ($result in $Results) {
        $serverCount++
        $Logger.LogInfo("Processing server $serverCount/$($Results.Count): $($result.Server)", "Debug")
        
        Write-Host "SERVER: $($result.Server)" -ForegroundColor Yellow
        $services = $result.Services
        
        $Logger.LogInfo("Server $($result.Server) has $($services.Count if $services else 0) services", "Debug")
        
        if ($services -and $services.Count -gt 0) {
            $totalServices += $services.Count
            $Logger.LogInfo("About to call WriteTable for $($services.Count) services", "Debug")
            try {
                $UserInteraction.WriteTable($services, @('Name','DisplayName','StartName','State'), @('Service Name','Display Name','Run As Account','Status'), @())
                $Logger.LogInfo("WriteTable completed successfully", "Debug")
            } catch {
                $Logger.LogError("WriteTable failed: $($_.Exception.Message)", "Debug")
                throw
            }
        } else {
            Write-Host "  No services found running as the service account." -ForegroundColor Gray
        }
        [UserInteraction]::WriteBlankLine()
    }
    
    if ($totalServices -eq 0) {
        [UserInteraction]::WriteActivity("No services found running as the service account on any server.", 'warning')
    } else {
        [UserInteraction]::WriteActivity("Found $totalServices service(s) across all servers.", 'info')
    }
    
    $Logger.LogInfo("Displayed service summary: $totalServices services across $($Results.Count) servers", "Automation")
}

function Confirm-ServicePasswordUpdate {
    param(
        [object[]]$Results,
        [object]$Logger,
        [object]$UserInteraction
    )
    # Count total services found
    $totalServices = 0
    foreach ($result in $Results) {
        if ($result.Services -and $result.Services.Count -gt 0) {
            $totalServices += $result.Services.Count
        }
    }
    
    if ($totalServices -eq 0) {
        [UserInteraction]::WriteActivity("No services found to update. Exiting.", 'warning')
        $Logger.LogWarning("No services found to update", "Automation")
        return $false
    }
    
    return $UserInteraction.PromptUserForConfirmation("Do you want to update the password for these $totalServices service(s)?")
}

function Update-ServicePasswordsOnAllServers {
    param(
        [object[]]$SessionInfos,
        [object[]]$Results,
        [string]$ServiceAccount,
        [securestring]$NewPassword,
        [object]$SessionHelper,
        [object]$UserInteraction,
        [object]$Logger
    )
    $updateServiceScript = {
        param($serviceName, $user, $securePassword)
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        )
        
        # Use Get-Service instead of WMI for service operations
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service) {
            # Stop the service before changing credentials
            if ($service.Status -eq 'Running') {
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            
            # Use sc.exe to change service credentials (more reliable than WMI)
            $result = & sc.exe config $serviceName obj= $user password= $plainPassword
            
            # Start the service back up
            Start-Service -Name $serviceName -ErrorAction SilentlyContinue
            
            return $LASTEXITCODE -eq 0
        } else {
            return $false
        }
    }
    foreach ($result in $Results) {
        $serverName = $result.Server
        $services = $result.Services
        $sessionInfo = $SessionInfos | Where-Object { $_.ServerName -eq ($serverName -split ' ')[0] }
        if ($sessionInfo -and $services) {
            foreach ($svc in $services) {
                if ($svc.Name -and $svc.Name -notlike '[ERROR*') {
                    $Logger.LogInfo("Updating password for service $($svc.Name) on $serverName", "Automation")
                    try {
                        $SessionHelper.ExecuteOnSession($sessionInfo.Session, $updateServiceScript, "Update password for $($svc.Name)", @($svc.Name, $ServiceAccount, $NewPassword))
                        $Logger.LogTaskOperation($serverName, $svc.Name, "Service Password Update", $true)
                    } catch {
                        $Logger.LogTaskOperation($serverName, $svc.Name, "Service Password Update", $false)
                        $Logger.LogError("Failed to update password for service '$($svc.Name)' on $serverName`: $($_.Exception.Message)", "Service Operation")
                    }
                }
            }
        }
    }
} 