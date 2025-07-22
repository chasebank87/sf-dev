using module core/AutomationScript.psm1
using module core/UserInteraction.psm1
using module core/Logger.psm1
using module core/DebugHelper.psm1

function Invoke-HealthMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [int]$CheckInterval = 5,
        [int]$Timeout = 3600
    )
    
    # Function entry logging
    $logger = Get-Logger
    $logger.LogInfo("=== HEALTH MONITOR FUNCTION START ===", "Health Monitor")
    $logger.LogInfo("Check interval: $CheckInterval seconds", "Health Monitor")
    $logger.LogInfo("Timeout: $Timeout seconds", "Health Monitor")
    
    # Initialize debug helper if not already initialized
    if (-not $Global:DebugHelper) {
        $logger.LogInfo("Initializing DebugHelper", "Health Monitor")
        Initialize-DebugHelper -Config $Config
    }
    $debugHelper = Get-DebugHelper
    $logger.LogInfo("Debug mode: $($debugHelper.IsDebug())", "Health Monitor")
    
    # Validate configuration
    $servers = $Config.servers
    $logger.LogInfo("Configuration validation:", "Health Monitor")
    $logger.LogInfo("- Servers count: $($servers.Count)", "Health Monitor")
    
    # Log server details
    foreach ($server in $servers) {
        $serverName = $server['name']
        $serverAddress = $server['address']
        $serverPorts = $server['ports']
        $logger.LogInfo("Configured server: $serverName ($serverAddress) - Ports: $($serverPorts.Count)", "Health Monitor")
        $logger.LogInfo("Server object type: $($server.GetType().Name)", "Health Monitor")
    }
    
    $startTime = Get-Date
    $logger.LogInfo("Process started at: $startTime", "Health Monitor")
    
    # Initialize status tracking
    $allServices = @{}
    $previousStatus = @{}
    $loggedErrors = @{}
    $servicesReady = $false
    $checkCount = 0
    
    # Build service list from all servers
    foreach ($server in $servers) {
        # Access hashtable properties correctly
        $serverName = $server['name']
        $serverAddress = $server['address']
        $serverPorts = $server['ports']
        
        $logger.LogInfo("Processing server: Name='$serverName', Address='$serverAddress', Ports count: $($serverPorts.Count)", "Health Monitor")
        
        if ($serverPorts) {
            foreach ($port in $serverPorts) {
                $serviceKey = "${serverName}:${port}"
                
                $allServices[$serviceKey] = [PSCustomObject]@{
                    Server = $serverName
                    Address = $serverAddress
                    Port = $port
                    Status = "Unknown"
                    LastCheck = $null
                }
                
                $logger.LogInfo("Added service: Server='$serverName', Port='$port'", "Health Monitor")
            }
        } else {
            $logger.LogWarning("Server '$serverName' has no ports defined", "Health Monitor")
        }
    }
    
    $logger.LogInfo("Total services to monitor: $($allServices.Count)", "Health Monitor")
    
        # Show initial status with all services as 'Unknown' before starting checks
    Clear-Host
    try {
        $logger.LogInfo("About to show initial health status", "Health Monitor")
        Show-HealthStatus -Services $allServices -CheckCount 0 -StartTime $startTime
        $logger.LogInfo("Initial health status displayed successfully", "Health Monitor")
    } catch {
        $logger.LogError("Error showing initial health status: $($_.Exception.Message)", "Health Monitor")
        [UserInteraction]::WriteActivity("Error displaying initial status: $($_.Exception.Message)", 'error')
        return $false
    }

    # Main monitoring loop
    $logger.LogInfo("Starting main monitoring loop - servicesReady: $servicesReady, timeout condition: $((Get-Date) - $startTime).TotalSeconds -lt $Timeout)", "Health Monitor")
    while (-not $servicesReady -and ((Get-Date) - $startTime).TotalSeconds -lt $Timeout) {
        try {
            $logger.LogInfo("[DIAG] Loop iteration START (CheckCount=$checkCount)", "Health Monitor")
            $checkCount++
            $currentTime = Get-Date
            $logger.LogInfo("=== CHECK #$checkCount at $currentTime ===", "Health Monitor")

            # Check all services
            $statusChanged = $false
            $readyCount = 0
            $totalCount = $allServices.Count

            foreach ($serviceKey in $allServices.Keys) {
                $service = $allServices[$serviceKey]
                $previousStatus[$serviceKey] = $service.Status

                $logger.LogInfo("[DIAG] Before Test-PortConnectivity for $serviceKey (Address=$($service.Address), Port=$($service.Port))", "Health Monitor")
                # Retry logic: up to 3 times, 0.3s timeout per attempt
                $maxRetries = 3
                $retryDelay = 0.3
                $portStatus = $false
                for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
                    $portStatus = Test-PortConnectivity -Server $service.Address -Port $service.Port -DebugHelper $debugHelper -LoggedErrors $loggedErrors -TimeoutSeconds $retryDelay
                    if ($portStatus) { break }
                    Start-Sleep -Seconds $retryDelay
                }
                $logger.LogInfo("[DIAG] After Test-PortConnectivity for $serviceKey", "Health Monitor")

                if ($portStatus) {
                    $service.Status = "Ready"
                    $readyCount++
                } else {
                    $service.Status = "Not Ready"
                }

                $service.LastCheck = $currentTime
                if ($previousStatus[$serviceKey] -ne $service.Status) {
                    $statusChanged = $true
                    $logger.LogInfo("Status changed for $serviceKey - $($previousStatus[$serviceKey]) to $($service.Status)", "Health Monitor")
                }
            }

            # Always refresh display after each check cycle
            $logger.LogInfo("[DIAG] Before Show-HealthStatus", "Health Monitor")
            $logger.LogInfo("Displaying health status - Status changed: $statusChanged, Check count: $checkCount", "Health Monitor")
            Clear-Host
            Show-HealthStatus -Services $allServices -CheckCount $checkCount -StartTime $startTime
            $logger.LogInfo("[DIAG] After Show-HealthStatus", "Health Monitor")

            # Check if all services are ready
            if ($readyCount -eq $totalCount) {
                $servicesReady = $true
                $logger.LogInfo("All services are ready! ($readyCount/$totalCount)", "Health Monitor")
                # All services are ready - break out of monitoring loop
                break
            }

            # Log progress
            $logger.LogInfo("Check #$checkCount completed - Ready: $readyCount/$totalCount", "Health Monitor")

            # Auto-continue checking with optional user interruption
            if (-not $servicesReady) {
                [UserInteraction]::WriteBlankLine()
                [UserInteraction]::WriteActivity("Press 'x' to quit, 'b' for menu, or Enter to check now", 'info')
                
                # Wait for CheckInterval seconds with persistent prompt, but allow user to interrupt
                $startWait = Get-Date
                while (((Get-Date) - $startWait).TotalSeconds -lt $CheckInterval) {
                    if ([System.Console]::KeyAvailable) {
                        $key = [System.Console]::ReadKey($true)
                        switch ($key.KeyChar.ToString().ToLower()) {
                            'x' { 
                                $logger.LogInfo("User chose to exit during wait", "Health Monitor")
                                break 3 
                            }
                            'b' { 
                                $logger.LogInfo("User chose to go back during wait", "Health Monitor")
                                return '__BACK__' 
                            }
                            "`r" { 
                                # Enter key - break out of wait and continue immediately
                                $logger.LogInfo("User chose to continue immediately", "Health Monitor")
                                break 
                            }
                            default { 
                                # Any other key - break out of wait and continue
                                $logger.LogInfo("User pressed key to continue", "Health Monitor")
                                break 
                            }
                        }
                        break
                    }
                    Start-Sleep -Milliseconds 100  # Check for input every 100ms
                }
            }
            $logger.LogInfo("[DIAG] Loop iteration END (CheckCount=$checkCount)", "Health Monitor")
        } catch {
            $logger.LogError("[DIAG] Exception in main loop: $($_.Exception.Message)", "Health Monitor")
            [UserInteraction]::WriteActivity("Exception in main loop: $($_.Exception.Message)", 'error')
            break
        }
    }
    
    # Final summary
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $logger.LogInfo("=== HEALTH MONITOR FUNCTION COMPLETE ===", "Health Monitor")
    $logger.LogInfo("Total duration: $($duration.ToString('hh\:mm\:ss'))", "Health Monitor")
    $logger.LogInfo("Total checks performed: $checkCount", "Health Monitor")
    $logger.LogInfo("All services ready: $servicesReady", "Health Monitor")
    
    # Show final status and require confirmation before returning to menu
    [UserInteraction]::WriteBlankLine()
    Write-Host "========================================" -ForegroundColor Cyan
    if ($servicesReady) {
        [UserInteraction]::WriteActivity("ALL SERVICES ARE READY! 🎉", 'info')
        [UserInteraction]::WriteBlankLine()
        [UserInteraction]::WriteActivity("All monitored services are now responding", 'info')
        [UserInteraction]::WriteActivity("Total Duration: $($duration.ToString('hh\:mm\:ss'))", 'info')
        [UserInteraction]::WriteActivity("Total Checks: $checkCount", 'info')
    } else {
        [UserInteraction]::WriteActivity("MONITORING STOPPED", 'warning')
        [UserInteraction]::WriteBlankLine()
        if (((Get-Date) - $startTime).TotalSeconds -ge $Timeout) {
            [UserInteraction]::WriteActivity("Timeout reached. Some services may not be ready.", 'warning')
        } else {
            [UserInteraction]::WriteActivity("User chose to stop monitoring.", 'warning')
        }
        [UserInteraction]::WriteActivity("Total Duration: $($duration.ToString('hh\:mm\:ss'))", 'info')
        [UserInteraction]::WriteActivity("Total Checks: $checkCount", 'info')
    }
    Write-Host "========================================" -ForegroundColor Cyan
    [UserInteraction]::WriteBlankLine()
    
    # Always require user confirmation before returning to menu
    $UserInteraction = Get-UserInteraction
    while ($true) {
        $finalChoice = $UserInteraction.PromptUserForConfirmation("Press 'b' to return to administration menu or 'x' to exit application")
        switch ($finalChoice.ToLower()) {
            'b' { 
                $logger.LogInfo("User chose to return to administration menu", "Health Monitor")
                return '__BACK__' 
            }
            'x' { 
                $logger.LogInfo("User chose to exit application from health monitor", "Health Monitor")
                return '__EXIT__'
            }
            default { 
                [UserInteraction]::WriteActivity("Invalid choice. Please press 'b' for menu or 'x' to exit.", 'error')
                continue
            }
        }
    }
}

function Test-PortConnectivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,
        [Parameter(Mandatory)]
        [string]$Port,
        [Parameter(Mandatory)]
        [object]$DebugHelper,
        [Parameter(Mandatory)]
        [hashtable]$LoggedErrors,
        [double]$TimeoutSeconds = 0.2
    )
    
    try {
        # Handle port ranges (e.g., "8205-8228")
        if ($Port -match "(\d+)-(\d+)") {
            $startPort = [int]$matches[1]
            $endPort = [int]$matches[2]
            $logger = Get-Logger
            
            # Test each port in the range
            for ($p = $startPort; $p -le $endPort; $p++) {
                $testCmd = "TcpClient test to $Server`:$p with ${TimeoutSeconds}s timeout"
                $logger = Get-Logger
                $logger.LogInfo("[DIAG] (Range) Before port $p on $Server", "Health Monitor")
                $debugHelper.LogCommand($testCmd, "Testing port $p on $Server with ${TimeoutSeconds}s timeout")

                if ($debugHelper.ShouldExecuteCommand("Test-NetConnection")) {
                    # Use TcpClient for faster, silent testing
                    try {
                        $tcpClient = New-Object System.Net.Sockets.TcpClient
                        $asyncResult = $tcpClient.BeginConnect($Server, $p, $null, $null)
                        $success = $asyncResult.AsyncWaitHandle.WaitOne([int]($TimeoutSeconds * 1000), $false)

                        if ($success) {
                            try {
                                $tcpClient.EndConnect($asyncResult)
                                $logger.LogInfo("Port $p on $Server is accessible", "Health Monitor")
                                $logger.LogInfo("[DIAG] (Range) After port $p on $Server (SUCCESS)", "Health Monitor")
                                return $true
                            } finally {
                                $tcpClient.Close()
                            }
                        } else {
                            $tcpClient.Close()
                            $logger.LogInfo("[DIAG] (Range) After port $p on $Server (TIMEOUT)", "Health Monitor")
                        }
                    } catch {
                        # Connection failed - continue to next port
                        if ($tcpClient) { $tcpClient.Close() }
                        $logger.LogInfo("[DIAG] (Range) After port $p on $Server (EXCEPTION)", "Health Monitor")
                    }
                } else {
                    # Debug mode - just log the command
                    $debugHelper.LogCommand($testCmd, "Testing port $p on $Server")
                    $logger.LogInfo("[DIAG] (Range) After port $p on $Server (DEBUG)", "Health Monitor")
                }
            }
            
            $logger.LogInfo("No ports in range $Port on $Server are accessible", "Health Monitor")
            return $false
        } else {
            # Single port test
            $testCmd = "TcpClient test to $Server`:$Port with ${TimeoutSeconds}s timeout"
            $debugHelper.LogCommand($testCmd, "Testing port $Port on $Server with ${TimeoutSeconds}s timeout")
            
            if ($debugHelper.ShouldExecuteCommand("Test-NetConnection")) {
                # Use TcpClient for faster, silent testing
                try {
                    $tcpClient = New-Object System.Net.Sockets.TcpClient
                    $asyncResult = $tcpClient.BeginConnect($Server, $Port, $null, $null)
                    $success = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000, $false)
                    
                    if ($success) {
                        try {
                            $tcpClient.EndConnect($asyncResult)
                            return $true
                        } finally {
                            $tcpClient.Close()
                        }
                    } else {
                        # Timeout occurred
                        $tcpClient.Close()
                        return $false
                    }
                } catch {
                    # Connection failed
                    if ($tcpClient) { $tcpClient.Close() }
                    return $false
                }
            } else {
                # Debug mode - just log the command
                return $false
            }
        }
    } catch {
        $logger = Get-Logger
        $errorKey = "${Server}:${Port}"
        $errorMessage = $_.Exception.Message
        
        # Only log each unique error once per server:port combination
        if (-not $LoggedErrors.ContainsKey($errorKey) -or $LoggedErrors[$errorKey] -ne $errorMessage) {
            $logger.LogError("Error testing port $Port on $Server - $errorMessage", "Health Monitor")
            $LoggedErrors[$errorKey] = $errorMessage
        }
        
        return $false
    }
}

function Get-PortDescription {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Port
    )
    
    # Port description mappings based on your configuration
    $portDescriptions = @{
        "80" = "DRM Web HTTP"
        "443" = "DRM Web HTTPS"
        "1423" = "Essbase"
        "5200-5400" = "DRM Service Ports"
        "5556" = "Node Manager"
        "6550" = "FDMEE HTTP"
        "7001" = "WebLogic Admin HTTP"
        "7010" = "Essbase Admin"
        "7363" = "HFM HTTP"
        "8200" = "Financial Reporting HTTP"
        "8205-8228" = "FR RMI Services"
        "8300" = "Planning HTTP"
        "8500" = "Calculation Manager HTTP"
        "13080" = "Provider Services"
        "9091" = "HFM Server"
        "9110" = "EAS Server"
        "10001-10020" = "HFM Datasource Range"
        "11333" = "Planning RMI"
        "12080" = "Essbase Studio HTTP"
        "19000" = "OHS HTTP"
        "20910" = "ODI Standalone Agent"
        "28080" = "Foundation Services HTTP"
        "31768-32768" = "Essbase Application Ports"
        "6712" = "OPMN"
        "10080" = "EAS HTTP"
    }
    
    if ($portDescriptions.ContainsKey($Port)) {
        return $portDescriptions[$Port]
    } else {
        return "Unknown Service"
    }
}

function Show-HealthStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Services,
        [int]$CheckCount,
        [datetime]$StartTime
    )
    
    $logger = Get-Logger
    $currentTime = Get-Date
    $duration = $currentTime - $StartTime
    $readyCount = 0
    $totalCount = $Services.Count
    
    # Calculate ready count
    foreach ($service in $Services.Values) {
        if ($service.Status -eq "Ready") {
            $readyCount++
        }
    }
    
    # Display header using standardized ShowScriptTitle
    [UserInteraction]::ShowScriptTitle("HEALTH MONITOR")
    [UserInteraction]::WriteBlankLine()
    Write-Host "Check #$CheckCount | Duration: $($duration.ToString('hh\:mm\:ss')) | Ready: $readyCount/$totalCount" -ForegroundColor White
    Write-Host "Last Updated: $($currentTime.ToString('HH:mm:ss'))" -ForegroundColor Gray
    [UserInteraction]::WriteBlankLine()
    
    # Group services by server and prepare data for table
    $serverGroups = $Services.Values | Group-Object -Property Server | Sort-Object Name
    
    $logger = Get-Logger
    $logger.LogInfo("Found $($serverGroups.Count) server groups", "Health Monitor")
    foreach ($group in $serverGroups) {
        $logger.LogInfo("Server group: Name='$($group.Name)', Count=$($group.Count)", "Health Monitor")
        # Log first few services in this group to debug
        $sampleServices = $group.Group | Select-Object -First 3
        foreach ($svc in $sampleServices) {
            $logger.LogInfo("Sample service in group: Server='$($svc.Server)', Port='$($svc.Port)', Address='$($svc.Address)'", "Health Monitor")
        }
    }
    
    foreach ($serverGroup in $serverGroups) {
        $serverName = if ($serverGroup.Name) { $serverGroup.Name } else { "Unknown Server" }
        $serverAddress = if ($serverGroup.Group[0].Address) { $serverGroup.Group[0].Address } else { "Unknown Address" }
        
        Write-Host "SERVER: $serverName" -ForegroundColor Yellow
        Write-Host "Address: $serverAddress" -ForegroundColor Gray
        [UserInteraction]::WriteBlankLine()
        
        # Prepare data for WriteTable function
        $tableData = @()
        foreach ($service in $serverGroup.Group | Sort-Object Port) {
            $statusText = if ($service.Status -eq "Ready") { "UP" } else { "DOWN" }
            $description = Get-PortDescription -Port $service.Port
            $lastCheck = if ($service.LastCheck) { $service.LastCheck.ToString('HH:mm:ss') } else { "Never" }
            
            $tableData += [PSCustomObject]@{
                Port = $service.Port
                Description = $description
                Status = $statusText
                LastCheck = $lastCheck
            }
        }
        
        # Use standardized WriteTable function with custom colors
        if ($tableData.Count -gt 0) {
            try {
                $logger.LogInfo("About to display table with $($tableData.Count) rows", "Health Monitor")
                
                # Define color mappings for status values
                $colorMappings = @{
                    "Status" = @{
                        "UP" = "Green"
                        "DOWN" = "Red"
                    }
                }
                
                # Use the global Write-Table function with color mappings
                Write-Table -Data $tableData -Columns @('Port', 'Description', 'Status', 'LastCheck') -Headers @('Port', 'Service Description', 'Status', 'Last Check') -ColorMappings $colorMappings
                $logger.LogInfo("Table displayed successfully", "Health Monitor")
            } catch {
                $logger.LogError("Error displaying table: $($_.Exception.Message)", "Health Monitor")
                [UserInteraction]::WriteActivity("Error displaying table: $($_.Exception.Message)", 'error')
                # Fallback to simple display
                Write-Host "Port | Description | Status | Last Check" -ForegroundColor Magenta
                Write-Host "-----|-----------|---------|-----------" -ForegroundColor Magenta
                foreach ($row in $tableData) {
                    $statusColor = if ($row.Status -eq "UP") { "Green" } else { "Red" }
                    Write-Host "$($row.Port) | $($row.Description) | " -NoNewline
                    Write-Host "$($row.Status)" -ForegroundColor $statusColor -NoNewline
                    Write-Host " | $($row.LastCheck)"
                }
            }
        } else {
            [UserInteraction]::WriteActivity("No services configured for this server", 'warning')
        }
        [UserInteraction]::WriteBlankLine()
    }
    
    # Progress bar using reusable UserInteraction method
    Write-InlineProgressBar -Current $readyCount -Total $totalCount -Label "Service Status"
    [UserInteraction]::WriteBlankLine()
    
    if ($readyCount -eq $totalCount) {
        [UserInteraction]::WriteActivity("ALL SERVICES ARE READY!", 'info')
    } else {
        [UserInteraction]::WriteActivity("Waiting for services to become ready...", 'warning')
    }
}