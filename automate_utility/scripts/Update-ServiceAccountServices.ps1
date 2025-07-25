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
    $allResults = Get-ServicesFromAllServers -SessionInfos $sessionInfos -ServiceAccount $serviceAccount -SessionHelper (Get-SessionHelper)

    Display-ServiceSummary -Results $allResults -UserInteraction $UserInteraction -Logger $logger

    if (-not (Confirm-ServicePasswordUpdate -Results $allResults -Logger $logger -UserInteraction $UserInteraction)) {
        return
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
        
        # Debug: Log what we're searching for
        Write-Host "DEBUG: Searching for service account: '$serviceAccount' on $env:COMPUTERNAME" -ForegroundColor Yellow
        
        # Helper function to normalize service account names for comparison
        function Compare-ServiceAccount {
            param($storedName, $searchAccount)
            
            if (-not $storedName -or -not $searchAccount) { return $false }
            
            # Convert both to lowercase for comparison
            $storedName = $storedName.ToLower()
            $searchAccount = $searchAccount.ToLower()
            
            # Direct match
            if ($storedName -eq $searchAccount) { 
                Write-Host "DEBUG: Direct match found - '$storedName'" -ForegroundColor Green
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
                Write-Host "DEBUG: Username match found - stored:'$storedName' -> user:'$storedUser', search:'$searchAccount' -> user:'$searchUser'" -ForegroundColor Green
                return $true
            }
            
            return $false
        }
        
        # Use Get-CimInstance to get service information
        $foundServices = @()
        $allServices = Get-CimInstance -ClassName Win32_Service
        Write-Host "DEBUG: Found $($allServices.Count) total services" -ForegroundColor Yellow
        
        $allServices | ForEach-Object {
            $serviceName = $_.Name
            $startName = $_.StartName
            Write-Host "DEBUG: Checking service '$serviceName' with StartName '$startName'" -ForegroundColor Cyan
            
            if (Compare-ServiceAccount -storedName $startName -searchAccount $serviceAccount) {
                Write-Host "DEBUG: MATCH! Adding service '$serviceName'" -ForegroundColor Green
                $foundServices += [PSCustomObject]@{
                    Name = $_.Name
                    DisplayName = $_.DisplayName
                    StartName = $_.StartName
                    State = $_.State
                }
            }
        }
        
        Write-Host "DEBUG: Found $($foundServices.Count) matching services" -ForegroundColor Yellow
        
        # Return the services array, or empty array if none found
        return $foundServices
    }
    $results = $SessionHelper.ExecuteOnMultipleSessions($SessionInfos, $getServicesScript, "Retrieve services running as $ServiceAccount", @($ServiceAccount))
    foreach ($sessionInfo in $SessionInfos) {
        $serverName = $sessionInfo.ServerName
        $serverInfo = $sessionInfo.ServerInfo
        $result = $results[$serverName]
        if ($result.Success) {
            $services = $result.Result
            $allResults += [PSCustomObject]@{
                Server = "$serverName ($($serverInfo.Address))"
                Services = $services
            }
        } else {
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
    [UserInteraction]::WriteBlankLine()
    $totalServices = 0
    foreach ($result in $Results) {
        Write-Host "SERVER: $($result.Server)" -ForegroundColor Yellow
        $services = $result.Services
        if ($services -and $services.Count -gt 0) {
            $totalServices += $services.Count
            $UserInteraction.WriteTable($services, @('Name','DisplayName','State'), @('Name','Display Name','State'), @())
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