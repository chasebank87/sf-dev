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
        Get-WmiObject Win32_Service | Where-Object { $_.StartName -eq $serviceAccount } |
            Select-Object Name, DisplayName, StartName, State
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
    foreach ($result in $Results) {
        Write-Host "SERVER: $($result.Server)" -ForegroundColor Yellow
        $services = $result.Services
        if ($services -and $services.Count -gt 0) {
            $UserInteraction.WriteTable($services, @('Name','DisplayName','State'), @('Name','Display Name','State'), @())
        } else {
            Write-Host "No services found running as the service account." -ForegroundColor Gray
        }
        [UserInteraction]::WriteBlankLine()
    }
    $Logger.LogInfo("Displayed service summary table with $($Results.Count) servers", "Automation")
}

function Confirm-ServicePasswordUpdate {
    param(
        [object[]]$Results,
        [object]$Logger,
        [object]$UserInteraction
    )
    $totalServices = ($Results | ForEach-Object { $_.Services.Count }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    if ($totalServices -eq 0) {
        [UserInteraction]::WriteActivity("No services found to update.", 'warning')
        $Logger.LogWarning("No services found to update", "Automation")
        return $false
    }
    return $UserInteraction.PromptUserForConfirmation("Do you want to update the password for these $totalServices services?")
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
        $service = Get-WmiObject Win32_Service -Filter "Name='$serviceName'"
        if ($service) {
            $service.Change($null, $null, $null, $null, $null, $null, $user, $plainPassword)
            $service.StopService() | Out-Null
            $service.StartService() | Out-Null
            return $true
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