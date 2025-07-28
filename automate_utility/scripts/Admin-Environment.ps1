using module core/AutomationScript.psm1
using module core/UserInteraction.psm1
using module core/Logger.psm1
using module core/DebugHelper.psm1
using module core/EncryptionHelper.psm1

function Invoke-AdminEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [object]$DebugHelper,
        [Parameter(Mandatory)]
        [ValidateSet('Start','Stop')]
        [string]$Mode
    )
    
    # Function entry logging
    $logger = [Logger]::GetInstance()
    $logger.LogInfo("=== ADMIN ENVIRONMENT FUNCTION START ===", "Admin Environment")
    $logger.LogInfo("Mode: $Mode", "Admin Environment")
    $logger.LogInfo("Config loaded: $($Config.servers.Count) servers configured", "Admin Environment")
    
    # Use passed debug helper
    $logger.LogInfo("Debug mode: $($DebugHelper.IsDebug())", "Admin Environment")
    
    # Validate configuration
    $servers = $Config.servers
    $logFolder = $Config.log_folder
    $encryptionKey = $Config.encryption_key
    
    $logger.LogInfo("Configuration validation:", "Admin Environment")
    $logger.LogInfo("- Servers count: $($servers.Count)", "Admin Environment")
    $logger.LogInfo("- Log folder: $logFolder", "Admin Environment")
    $logger.LogInfo("- Encryption key provided: $(-not [string]::IsNullOrEmpty($encryptionKey))", "Admin Environment")
    
    # Log server details
    foreach ($server in $servers) {
        $logger.LogInfo("Configured server: $($server.name) ($($server.address))", "Admin Environment")
    }
    
    # Initialize encryption helper
    try {
        $logger.LogInfo("Initializing EncryptionHelper", "Admin Environment")
        Initialize-EncryptionHelper -Key $encryptionKey
        $encryptionHelper = Get-EncryptionHelper
        $logger.LogInfo("EncryptionHelper initialized successfully", "Admin Environment")
    } catch {
        $logger.LogError("Failed to initialize EncryptionHelper: $_", "Admin Environment")
        throw
    }
    
    $actionVerb = if ($Mode -eq 'Start') { 'Starting' } else { 'Stopping' }
    $scAction = if ($Mode -eq 'Start') { 'start' } else { 'stop' }
    
    $logger.LogInfo("Action verb: $actionVerb, SC action: $scAction", "Admin Environment")

    $stepNum = 0
    $totalSteps = 6
    $startTime = Get-Date
    $logger.LogInfo("Process started at: $startTime", "Admin Environment")

    # Section 1: Admin Services
    $stepNum++
    $logger.LogInfo("=== SECTION $stepNum of $totalSteps - ADMIN SERVICES ===", "Admin Environment")
    Write-Progress -Id 1 -Activity "$actionVerb Environment" -Status "Section 1/6: Admin Services" -PercentComplete ([Math]::Round(($stepNum/$totalSteps)*100))
    
    $adminServices = @(
        @{ Name = 'wlsvc EPMSystem_AdminServer'; Server = 'phx-epmap-wd001' },
        @{ Name = 'wlsvc ODI_domain_AdminServer'; Server = 'phx-epmap-wd004' }
    )
    $logger.LogInfo("Admin services to process: $($adminServices.Count)", "Admin Environment")
    
    $processedCount = 0
    $skippedCount = 0
    $errorCount = 0
    
    foreach ($svc in $adminServices) {
        $logger.LogInfo("Processing service: $($svc.Name) on $($svc.Server)", "Admin Environment")
        
        $server = $servers | Where-Object { $_.name -eq $svc.Server }
        if (-not $server) { 
            $logger.LogWarning("Server $($svc.Server) not found in config. Skipping $($svc.Name).", "Admin Environment")
            Write-Host "[WARN] Server $($svc.Server) not found in config. Skipping $($svc.Name)." -ForegroundColor Yellow
            $skippedCount++
            continue 
        }
        
        try {
            $logger.LogInfo("$actionVerb $($svc.Name) on $($svc.Server)", "Admin Environment")
            Write-Host "[$actionVerb] $($svc.Name) on $($svc.Server) ..." -ForegroundColor Cyan
            
            $scCmd = "sc \\$($svc.Server) $scAction `"$($svc.Name)`""
            $debugHelper.LogCommand($scCmd, "$actionVerb $($svc.Name) on $($svc.Server)")
            
            $output = $debugHelper.ExecuteOrDebug({ Invoke-Expression $scCmd }, "$actionVerb $($svc.Name) on $($svc.Server)", "sc")
            $logger.LogInfo("Service command output: $output", "Admin Environment")
            $processedCount++
            
        } catch {
            $logger.LogError("Failed to $actionVerb $($svc.Name) on $($svc.Server): $_", "Admin Environment")
            Write-Host "[ERROR] Failed to $actionVerb $($svc.Name) on $($svc.Server): $_" -ForegroundColor Red
            $errorCount++
        }
    }
    
    $logger.LogInfo("Section 1 completed - Processed: $processedCount, Skipped: $skippedCount, Errors: $errorCount", "Admin Environment")
    $logger.LogInfo("Waiting 2 seconds before next section...", "Admin Environment")
    Start-Sleep -Seconds 240

    # Section 2: OHS/NodeManagers/Foundation/ODI domain services
    $stepNum++
    $logger.LogInfo("=== SECTION $stepNum of $totalSteps - OHS/NODEMANAGERS/FOUNDATION/ODI DOMAIN ===", "Admin Environment")
    Write-Progress -Id 1 -Activity "$actionVerb Environment" -Status "Section 2/6: OHS/NodeManagers/Foundation/ODI domain" -PercentComplete ([Math]::Round(($stepNum/$totalSteps)*100))
    
    $section2 = @(
        @{ Name = 'Oracle Weblogic ohs NodeManager (D Hyperion ohs wlserver)'; Server = 'phx-epmap-wd001' },
        @{ Name = 'Oracle Weblogic ohs NodeManager (D_Hyperion_ohs_wlserver)'; Server = 'phx-epmap-wd002' },
        @{ Name = 'wlsvc ODI_domain_ODI_server1'; Server = 'phx-epmap-wd004' },
        @{ Name = 'HyS9FoundationServices_Foundation'; Server = 'phx-epmap-wd001' }
    )
    $logger.LogInfo("Section 2 services to process: $($section2.Count)", "Admin Environment")
    
    $processedCount = 0
    $skippedCount = 0
    $errorCount = 0
    
    foreach ($svc in $section2) {
        $logger.LogInfo("Processing service: $($svc.Name) on $($svc.Server)", "Admin Environment")
        
        $server = $servers | Where-Object { $_.name -eq $svc.Server }
        if (-not $server) { 
            $logger.LogWarning("Server $($svc.Server) not found in config. Skipping $($svc.Name).", "Admin Environment")
            Write-Host "[WARN] Server $($svc.Server) not found in config. Skipping $($svc.Name)." -ForegroundColor Yellow
            $skippedCount++
            continue 
        }
        
        try {
            $logger.LogInfo("$actionVerb $($svc.Name) on $($svc.Server)", "Admin Environment")
            Write-Host "[$actionVerb] $($svc.Name) on $($svc.Server) ..." -ForegroundColor Cyan
            
            $scCmd = "sc \\$($svc.Server) $scAction `"$($svc.Name)`""
            $debugHelper.LogCommand($scCmd, "$actionVerb $($svc.Name) on $($svc.Server)")
            
            $output = $debugHelper.ExecuteOrDebug({ Invoke-Expression $scCmd }, "$actionVerb $($svc.Name) on $($svc.Server)", "sc")
            $logger.LogInfo("Service command output: $output", "Admin Environment")
            $processedCount++
            
        } catch {
            $logger.LogError("Failed to $actionVerb $($svc.Name) on $($svc.Server): $_", "Admin Environment")
            Write-Host "[ERROR] Failed to $actionVerb $($svc.Name) on $($svc.Server): $_" -ForegroundColor Red
            $errorCount++
        }
    }
    
    $logger.LogInfo("Section 2 completed - Processed: $processedCount, Skipped: $skippedCount, Errors: $errorCount", "Admin Environment")
    $logger.LogInfo("Waiting 2 seconds before next section...", "Admin Environment")
    Start-Sleep -Seconds 280

    # Section 3: Second Foundation and OHS scripts (internal logic)
    $stepNum++
    Write-Progress -Id 1 -Activity "$actionVerb Environment" -Status "Section 3/6: Second Foundation & OHS" -PercentComplete ([Math]::Round(($stepNum/$totalSteps)*100))
    # Foundation2
    $foundation2 = @{ Name = 'HyS9FoundationServices_Foundation2'; Server = 'phx-epmap-wd002' }
    $server = $servers | Where-Object { $_.name -eq $foundation2.Server }
    if ($server) {
        $logger.LogInfo("$actionVerb $($foundation2.Name) on $($foundation2.Server)", "Admin Environment")
        Write-Host "[$actionVerb] $($foundation2.Name) on $($foundation2.Server) ..." -ForegroundColor Cyan
        $scCmd = "sc \\$($foundation2.Server) ${scAction} `"$($foundation2.Name)`""
        $debugHelper.LogCommand($scCmd, "$actionVerb $($foundation2.Name) on $($foundation2.Server)")
        $output = $debugHelper.ExecuteOrDebug({ Invoke-Expression $scCmd }, "$actionVerb $($foundation2.Name) on $($foundation2.Server)", "sc")
        $logger.LogInfo($output, "Admin Environment")
    }
    # OHS1/OHS2 logic (simulate decrypting pfile and using it)
    $pfilePath = "$PSScriptRoot/../config/pfile.txt"
    if (Test-Path $pfilePath) {
        $encryptedPfile = Get-Content $pfilePath -Raw
        $debugHelper.LogCommand("Get-Content $pfilePath -Raw", "Reading encrypted pfile")
        $decryptedPfile = $debugHelper.ExecuteOrDebug({ $encryptionHelper.Decrypt($encryptedPfile) }, "Decrypting pfile", "EncryptionHelper")
        $logger.LogInfo("Decrypted pfile for OHS: $decryptedPfile", "Admin Environment")
        Write-Host "[OHS1] Would use decrypted pfile: $decryptedPfile" -ForegroundColor Cyan
        Write-Host "[OHS2] Would use decrypted pfile: $decryptedPfile" -ForegroundColor Cyan
    } else {
        Write-Host "[WARN] pfile.txt not found for OHS1/OHS2." -ForegroundColor Yellow
    }
    Start-Sleep -Seconds 20

    # Section 4: Reporting and RMI services
    $section4 = @(
        @{ Name = 'HyS9FRReports_Foundation'; Server = 'phx-epmap-wd001' },
        @{ Name = 'HyS9FRReports_Foundation2'; Server = 'phx-epmap-wd002' },
        @{ Name = 'HyS9RMIRegistry_Foundation'; Server = 'phx-epmap-wd001' }
    )
    $stepNum++
    Write-Progress -Id 1 -Activity "$actionVerb Environment" -Status "Section 4/6: Reporting & RMI" -PercentComplete ([Math]::Round(($stepNum/$totalSteps)*100))
    foreach ($svc in $section4) {
        $server = $servers | Where-Object { $_.name -eq $svc.Server }
        if (-not $server) { Write-Host "[WARN] Server $($svc.Server) not found in config. Skipping $($svc.Name)." -ForegroundColor Yellow; continue }
        $logger.LogInfo("$actionVerb $($svc.Name) on $($svc.Server)", "Admin Environment")
        Write-Host "[${actionVerb}] $($svc.Name) on $($svc.Server) ..." -ForegroundColor Cyan
        $scCmd = "sc \\$($svc.Server) ${scAction} `"$($svc.Name)`""
        $debugHelper.LogCommand($scCmd, "$actionVerb $($svc.Name) on $($svc.Server)")
        $output = $debugHelper.ExecuteOrDebug({ Invoke-Expression $scCmd }, "$actionVerb $($svc.Name) on $($svc.Server)", "sc")
        $logger.LogInfo($output, "Admin Environment")
    }
    Start-Sleep -Seconds 20

    # Section 5: All HyS9* except FDM
    $stepNum++
    Write-Progress -Id 1 -Activity "$actionVerb Environment" -Status "Section 5/6: All HyS9* except FDM" -PercentComplete ([Math]::Round(($stepNum/$totalSteps)*100))
    foreach ($srv in $servers) {
        try {
            $getServiceCmd = "Get-Service -ComputerName $($srv.name) | Where-Object { `$_.ServiceName -like 'HyS9*' -and `$_.ServiceName -notlike '*FDM*' }"
            $debugHelper.LogCommand($getServiceCmd, "Discovering HyS9* services (excluding FDM) on $($srv.name)")
            $hyS9Services = $debugHelper.ExecuteOrDebug({ Get-Service -ComputerName $srv.name | Where-Object { $_.ServiceName -like 'HyS9*' -and $_.ServiceName -notlike '*FDM*' } }, "Discovering HyS9* services on $($srv.name)", "Get-Service")
            foreach ($svc in $hyS9Services) {
                $logger.LogInfo("$actionVerb $($svc.ServiceName) on $($srv.name)", "Admin Environment")
                Write-Host "[${actionVerb}] $($svc.ServiceName) on $($srv.name) ..." -ForegroundColor Cyan
                $scCmd = "sc \\$($srv.name) ${scAction} `"$($svc.ServiceName)`""
                $debugHelper.LogCommand($scCmd, "$actionVerb $($svc.ServiceName) on $($srv.name)")
                $output = $debugHelper.ExecuteOrDebug({ Invoke-Expression $scCmd }, "$actionVerb $($svc.ServiceName) on $($srv.name)", "sc")
                $logger.LogInfo($output, "Admin Environment")
            }
        } catch {
            Write-Host "[ERROR] Could not query HyS9 services on $($srv.name): $_" -ForegroundColor Red
            $logger.LogError($_, "Admin Environment")
        }
    }
    Start-Sleep -Seconds 180

    # Section 6: FDM services
    $stepNum++
    Write-Progress -Id 1 -Activity "$actionVerb Environment" -Status "Section 6/6: FDM" -PercentComplete ([Math]::Round(($stepNum/$totalSteps)*100))
    foreach ($srv in $servers) {
        try {
            $getServiceCmd = "Get-Service -ComputerName $($srv.name) | Where-Object { `$_.ServiceName -like '*FDM*' }"
            $debugHelper.LogCommand($getServiceCmd, "Discovering FDM services on $($srv.name)")
            $fdmServices = $debugHelper.ExecuteOrDebug({ Get-Service -ComputerName $srv.name | Where-Object { $_.ServiceName -like '*FDM*' } }, "Discovering FDM services on $($srv.name)", "Get-Service")
            foreach ($svc in $fdmServices) {
                $logger.LogInfo("$actionVerb $($svc.ServiceName) on $($srv.name)", "Admin Environment")
                Write-Host "[${actionVerb}] $($svc.ServiceName) on $($srv.name) ..." -ForegroundColor Cyan
                $scCmd = "sc \\$($srv.name) ${scAction} `"$($svc.ServiceName)`""
                $debugHelper.LogCommand($scCmd, "$actionVerb $($svc.ServiceName) on $($srv.name)")
                $output = $debugHelper.ExecuteOrDebug({ Invoke-Expression $scCmd }, "$actionVerb $($svc.ServiceName) on $($srv.name)", "sc")
                $logger.LogInfo($output, "Admin Environment")
            }
        } catch {
            Write-Host "[ERROR] Could not query FDM services on $($srv.name): $_" -ForegroundColor Red
            $logger.LogError($_, "Admin Environment")
        }
    }
    Start-Sleep -Seconds 2

    Write-Progress -Id 1 -Activity "$actionVerb Environment" -Status "Completed" -PercentComplete 100 -Completed
    
    # Final summary logging
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $logger.LogInfo("=== ADMIN ENVIRONMENT FUNCTION COMPLETE ===", "Admin Environment")
    $logger.LogInfo("Mode: $Mode", "Admin Environment")
    $logger.LogInfo("Start time: $startTime", "Admin Environment")
    $logger.LogInfo("End time: $endTime", "Admin Environment")
    $logger.LogInfo("Total duration: $($duration.ToString('hh\:mm\:ss'))", "Admin Environment")
    $logger.LogInfo("Debug mode was: $($debugHelper.IsDebug())", "Admin Environment")
    $logger.LogInfo("Configuration used:", "Admin Environment")
    $logger.LogInfo("- Servers configured: $($servers.Count)", "Admin Environment")
    $logger.LogInfo("- Log folder: $logFolder", "Admin Environment")
    $logger.LogInfo("- Encryption key provided: $(-not [string]::IsNullOrEmpty($encryptionKey))", "Admin Environment")
    
    Write-Host "[$actionVerb] Environment process complete." -ForegroundColor Green
    Write-Host "Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
}