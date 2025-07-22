Import-Module "$PSScriptRoot/../core/DebugHelper.psm1" -Force
Import-Module "$PSScriptRoot/../core/UserInteraction.psm1" -Force

function Invoke-HealthMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [int]$CheckInterval = 30,
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
    Show-HealthStatus -Services $allServices -CheckCount 0 -StartTime $startTime
    
    # Main monitoring loop
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
                # Test port connectivity
                $portStatus = Test-PortConnectivity -Server $service.Address -Port $service.Port -DebugHelper $debugHelper -LoggedErrors $loggedErrors -TimeoutSeconds 2
                $logger.LogInfo("[DIAG] After Test-PortConnectivity for $serviceKey", "Health Monitor")

                if ($portStatus) {
                    $service.Status = "Ready"
                    $readyCount++
                } else {
                    $service.Status = "Not Ready"
                }

                $service.LastCheck = $currentTime
                # Check if status changed
                if ($previousStatus[$serviceKey] -ne $service.Status) {
                    $statusChanged = $true
                    $logger.LogInfo("Status changed for $serviceKey - $($previousStatus[$serviceKey]) to $($service.Status)", "Health Monitor")
                }
            }

            # Check if all services are ready
            if ($readyCount -eq $totalCount) {
                $servicesReady = $true
                $logger.LogInfo("All services are ready! ($readyCount/$totalCount)", "Health Monitor")
            }

            # Display status (clear screen if status changed or first check)
            $logger.LogInfo("[DIAG] Before Show-HealthStatus", "Health Monitor")
            if ($statusChanged -or $checkCount -eq 1) {
                $logger.LogInfo("Displaying health status - Status changed: $statusChanged, Check count: $checkCount", "Health Monitor")
                Clear-Host
                Show-HealthStatus -Services $allServices -CheckCount $checkCount -StartTime $startTime
            }
            $logger.LogInfo("[DIAG] After Show-HealthStatus", "Health Monitor")

            # Log progress
            $logger.LogInfo("Check #$checkCount completed - Ready: $readyCount/$totalCount", "Health Monitor")

            # Wait before next check (unless all services are ready)
            if (-not $servicesReady) {
                $logger.LogInfo("[DIAG] Before Start-Sleep", "Health Monitor")
                $logger.LogInfo("Waiting $CheckInterval seconds before next check...", "Health Monitor")
                Start-Sleep -Seconds $CheckInterval
                $logger.LogInfo("[DIAG] After Start-Sleep", "Health Monitor")
            }
            $logger.LogInfo("[DIAG] Loop iteration END (CheckCount=$checkCount)", "Health Monitor")
        } catch {
            $logger.LogError("[DIAG] Exception in main loop: $($_.Exception.Message)", "Health Monitor")
            Write-Host "[DIAG] Exception in main loop: $($_.Exception.Message)" -ForegroundColor Red
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
    
    if ($servicesReady) {
        Write-Host "✅ All services are ready!" -ForegroundColor Green
        Write-Host "Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
        Write-Host "Checks performed: $checkCount" -ForegroundColor Cyan
    } else {
        Write-Host "⏰ Timeout reached. Some services may not be ready." -ForegroundColor Yellow
        Write-Host "Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
        Write-Host "Checks performed: $checkCount" -ForegroundColor Cyan
    }
    
    return $servicesReady
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
    
    # Display header
    Write-Host "HEALTH MONITOR - REAL-TIME STATUS" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "Check #$CheckCount | Duration: $($duration.ToString('hh\:mm\:ss')) | Ready: $readyCount/$totalCount" -ForegroundColor White
    Write-Host "Last Updated: $($currentTime.ToString('HH:mm:ss'))" -ForegroundColor Gray
    Write-Host ""
    
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
        Write-Host ""
        
        # Display table header manually to handle colored status
        Write-Host "Port             | Service Description            | Status | Last Check" -ForegroundColor Magenta
        Write-Host "-----------------|--------------------------------|--------|------------" -ForegroundColor Magenta
        
        # Display each row with colored status
        foreach ($service in $serverGroup.Group | Sort-Object Port) {
            $statusText = if ($service.Status -eq "Ready") { "UP" } else { "DOWN" }
            $statusColor = if ($service.Status -eq "Ready") { "Green" } else { "Red" }
            $description = Get-PortDescription -Port $service.Port
            $lastCheck = if ($service.LastCheck) { $service.LastCheck.ToString('HH:mm:ss') } else { "Never" }
            
            # Format each column with proper spacing (wider port column for ranges)
            $portCol = $service.Port.PadRight(16)
            $serviceCol = $description.PadRight(30)
            $statusCol = $statusText.PadRight(6)
            $timeCol = $lastCheck
            
            Write-Host "$portCol | $serviceCol | " -NoNewline -ForegroundColor White
            Write-Host $statusCol -NoNewline -ForegroundColor $statusColor
            Write-Host " | $timeCol" -ForegroundColor White
        }
        Write-Host ""
    }
    
    # Progress bar
    $percentage = if ($totalCount -gt 0) { [Math]::Round(($readyCount / $totalCount) * 100) } else { 0 }
    $filledBlocks = [Math]::Floor($percentage / 5)
    $emptyBlocks = 20 - $filledBlocks
    $progressBar = ("#" * $filledBlocks) + ("-" * $emptyBlocks)
    Write-Host "Progress: [$progressBar] $percentage%" -ForegroundColor Cyan
    Write-Host ""
    
    if ($readyCount -eq $totalCount) {
        Write-Host "ALL SERVICES ARE READY!" -ForegroundColor Green
    } else {
        Write-Host "Waiting for services to become ready..." -ForegroundColor Yellow
    }
}

Export-ModuleMember -Function Invoke-HealthMonitor 