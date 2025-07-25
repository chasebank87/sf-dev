using module .\Logger.psm1
using module .\DebugHelper.psm1
using module .\UserInteraction.psm1

class SessionPool {
    [hashtable]$Sessions = @{}
    [hashtable]$LastUsed = @{}
    [int]$MaxIdleMinutes = 30
    
    [void]AddSession([string]$ServerAddress, [object]$Session) {
        $this.Sessions[$ServerAddress] = $Session
        $this.LastUsed[$ServerAddress] = Get-Date
    }
    
    [object]GetSession([string]$ServerAddress) {
        if ($this.Sessions.ContainsKey($ServerAddress)) {
            $this.LastUsed[$ServerAddress] = Get-Date
            return $this.Sessions[$ServerAddress]
        }
        return $null
    }
    
    [void]RemoveSession([string]$ServerAddress) {
        if ($this.Sessions.ContainsKey($ServerAddress)) {
            try {
                Remove-PSSession -Session $this.Sessions[$ServerAddress] -ErrorAction SilentlyContinue
            } catch {
                # Ignore cleanup errors
            }
            $this.Sessions.Remove($ServerAddress)
            $this.LastUsed.Remove($ServerAddress)
        }
    }
    
    [void]CleanupIdleSessions() {
        $cutoffTime = (Get-Date).AddMinutes(-$this.MaxIdleMinutes)
        $expiredSessions = @()
        
        foreach ($serverAddress in $this.LastUsed.Keys) {
            if ($this.LastUsed[$serverAddress] -lt $cutoffTime) {
                $expiredSessions += $serverAddress
            }
        }
        
        foreach ($serverAddress in $expiredSessions) {
            $this.RemoveSession($serverAddress)
        }
    }
    
    [void]CleanupAllSessions() {
        foreach ($serverAddress in @($this.Sessions.Keys)) {
            $this.RemoveSession($serverAddress)
        }
    }
    
    [int]GetActiveSessionCount() {
        return $this.Sessions.Count
    }
}

class SessionHelper {
    [object]$Config
    [object]$Logger
    [object]$UserInteraction
    [SessionPool]$SessionPool
    [hashtable]$ServerCache = @{}
    [int]$DefaultRetryCount = 3
    [int]$DefaultRetryDelaySeconds = 2
    [int]$DefaultConnectionTimeoutSeconds = 30
    
    SessionHelper([object]$Config) {
        $this.Config = $Config
        $this.Logger = Get-Logger
        $this.UserInteraction = Get-UserInteraction
        $this.SessionPool = [SessionPool]::new()
        
        # Pre-validate and cache server configurations
        $this.InitializeServerCache()
        
        $this.Logger.LogInfo("SessionHelper initialized with $($this.ServerCache.Count) servers", "Session Management")
    }
    
    # Dynamic property to always get the current DebugHelper instance
    [object] GetDebugHelper() {
        try {
            return Get-DebugHelper
        } catch {
            $this.Logger.LogError("DebugHelper not available: $($_.Exception.Message)", "Session Management")
            throw "DebugHelper not initialized. Ensure Initialize-DebugHelper is called before using SessionHelper."
        }
    }
    
    [void]InitializeServerCache() {
        if (-not $this.Config.servers) {
            throw "No servers configured in config"
        }
        
        foreach ($server in $this.Config.servers) {
            if (-not $server.name -or -not $server.address) {
                $this.Logger.LogWarning("Invalid server configuration: missing name or address", "Server Validation")
                continue
            }
            
            $this.ServerCache[$server.name] = @{
                Name = $server.name
                Address = $server.address
                Tasks = if ($server.tasks) { $server.tasks } else { @() }
                Ports = if ($server.ports) { $server.ports } else { @() }
                IsValidated = $false
            }
        }
        
        if ($this.ServerCache.Count -eq 0) {
            throw "No valid servers found in configuration"
        }
    }
    
    [object]GetServerInfo([string]$ServerName) {
        if ($this.ServerCache.ContainsKey($ServerName)) {
            return $this.ServerCache[$ServerName]
        }
        return $null
    }
    
    [string[]]GetAllServerNames() {
        return @($this.ServerCache.Keys)
    }
    
    [bool]ValidateServerExists([string]$ServerName) {
        return $this.ServerCache.ContainsKey($ServerName)
    }
    
    [object]CreateSession([string]$ServerName, [bool]$UsePool = $true) {
        $serverInfo = $this.GetServerInfo($ServerName)
        if (-not $serverInfo) {
            throw "Server '$ServerName' not found in configuration"
        }
        
        $serverAddress = $serverInfo.Address
        
        # Check if we have a pooled session
        if ($UsePool) {
            $existingSession = $this.SessionPool.GetSession($serverAddress)
            if ($existingSession -and $this.TestSessionHealth($existingSession)) {
                $this.Logger.LogInfo("Reusing existing session for $ServerName ($serverAddress)", "Session Management")
                return $existingSession
            } elseif ($existingSession) {
                # Session exists but unhealthy, remove it
                $this.SessionPool.RemoveSession($serverAddress)
                $this.Logger.LogWarning("Removed unhealthy session for $ServerName", "Session Management")
            }
        }
        
        # Create new session with retry logic
        $session = $this.CreateSessionWithRetry($serverAddress, $ServerName)
        
        if ($UsePool) {
            $this.SessionPool.AddSession($serverAddress, $session)
        }
        
        return $session
    }
    
    [object]CreateSessionWithRetry([string]$ServerAddress, [string]$ServerName) {
        $attempt = 0
        $lastException = $null
        
        while ($attempt -lt $this.DefaultRetryCount) {
            $attempt++
            
            try {
                [UserInteraction]::WriteActivity("Creating session to $ServerName ($ServerAddress) - Attempt $attempt/$($this.DefaultRetryCount)", 'info')
                $this.Logger.LogInfo("Creating PowerShell session to $ServerName ($ServerAddress) - Attempt $attempt", "Session Management")
                
                $session = $this.GetDebugHelper().NewPSSessionOrDebug($ServerAddress, "Creating session to $ServerName")
                
                # Test the session immediately
                if ($this.TestSessionHealth($session)) {
                    $this.Logger.LogInfo("Successfully created session to $ServerName ($ServerAddress)", "Session Management")
                    [UserInteraction]::WriteActivity("Successfully connected to $ServerName", 'info')
                    return $session
                } else {
                    throw "Session health check failed"
                }
                
            } catch {
                $lastException = $_
                $this.Logger.LogWarning("Session creation attempt $attempt failed for $ServerName`: $($_.Exception.Message)", "Session Management")
                
                if ($attempt -lt $this.DefaultRetryCount) {
                    [UserInteraction]::WriteActivity("Connection failed, retrying in $($this.DefaultRetryDelaySeconds) seconds...", 'warning')
                    Start-Sleep -Seconds $this.DefaultRetryDelaySeconds
                }
            }
        }
        
        # All attempts failed
        $errorMsg = "Failed to create session to $ServerName ($ServerAddress) after $($this.DefaultRetryCount) attempts. Last error: $($lastException.Exception.Message)"
        $this.Logger.LogError($errorMsg, "Session Management")
        [UserInteraction]::WriteActivity($errorMsg, 'error')
        throw $lastException
    }
    
    [bool]TestSessionHealth([object]$Session) {
        if (-not $Session) {
            return $false
        }
        
        try {
            # Test if session is still responsive
            $result = Invoke-Command -Session $Session -ScriptBlock { Get-Date } -ErrorAction Stop
            return $result -ne $null
        } catch {
            return $false
        }
    }
    
    [object[]]CreateMultipleSessions([string[]]$ServerNames, [bool]$UsePool = $true) {
        $sessions = @()
        $failedServers = @()
        
        $progressBar = $this.UserInteraction.InitializeProgressBar($ServerNames.Count, "Creating sessions to servers")
        
        foreach ($serverName in $ServerNames) {
            try {
                $session = $this.CreateSession($serverName, $UsePool)
                $sessions += @{
                    ServerName = $serverName
                    Session = $session
                    ServerInfo = $this.GetServerInfo($serverName)
                }
                $this.UserInteraction.UpdateProgressBar($progressBar, 1, "Connected to $serverName")
            } catch {
                $failedServers += $serverName
                $this.Logger.LogError("Failed to create session to $serverName`: $($_.Exception.Message)", "Session Management")
                $this.UserInteraction.UpdateProgressBar($progressBar, 1, "Failed: $serverName")
            }
        }
        
        $this.UserInteraction.CompleteProgressBar($progressBar)
        
        if ($failedServers.Count -gt 0) {
            [UserInteraction]::WriteActivity("Failed to connect to $($failedServers.Count) servers: $($failedServers -join ', ')", 'warning')
        }
        
        $this.Logger.LogInfo("Created $($sessions.Count) sessions out of $($ServerNames.Count) requested", "Session Management")
        return $sessions
    }
    
    [object]ExecuteOnSession([object]$Session, [scriptblock]$ScriptBlock, [string]$Description, [object[]]$ArgumentList = @()) {
        try {
            $this.Logger.LogInfo("Executing command on session: $Description", "Session Execution")
            
            # Use DebugHelper to analyze script block for security (proper separation of concerns)
            $debugHelper = $this.GetDebugHelper()
            $this.Logger.LogInfo("DebugHelper retrieved successfully", "Session Execution")
            $commandType = $debugHelper.AnalyzeScriptBlockForCommandType($ScriptBlock)
            $this.Logger.LogInfo("Command type determined: $commandType", "Session Execution")
            
            # Always pass ArgumentList, even if empty, to avoid overload issues
            return $debugHelper.InvokeOrDebug($Session, $ScriptBlock, $Description, $commandType, $ArgumentList)
        } catch {
            $this.Logger.LogError("Failed to execute command on session: $Description - $($_.Exception.Message)", "Session Execution")
            throw
        }
    }

    # Overload that allows explicitly specifying the command type
    [object]ExecuteOnSession([object]$Session, [scriptblock]$ScriptBlock, [string]$Description, [string]$CommandType, [object[]]$ArgumentList = @()) {
        try {
            $this.Logger.LogInfo("Executing command on session: $Description (explicit command type: $CommandType)", "Session Execution")
            
            # Always pass ArgumentList, even if empty, to avoid overload issues
            return $this.GetDebugHelper().InvokeOrDebug($Session, $ScriptBlock, $Description, $CommandType, $ArgumentList)
        } catch {
            $this.Logger.LogError("Failed to execute command on session: $Description - $($_.Exception.Message)", "Session Execution")
            throw
        }
    }


    
    [hashtable]ExecuteOnMultipleSessions([object[]]$Sessions, [scriptblock]$ScriptBlock, [string]$Description, [object[]]$ArgumentList = @()) {
        $results = @{}
        $progressBar = $this.UserInteraction.InitializeProgressBar($Sessions.Count, "Executing: $Description")
        
        foreach ($sessionInfo in $Sessions) {
            $serverName = $sessionInfo.ServerName
            $session = $sessionInfo.Session
            
            try {
                $result = $this.ExecuteOnSession($session, $ScriptBlock, "$Description on $serverName", $ArgumentList)
                $results[$serverName] = @{
                    Success = $true
                    Result = $result
                    Error = $null
                }
                $this.UserInteraction.UpdateProgressBar($progressBar, 1, "Completed: $serverName")
            } catch {
                $results[$serverName] = @{
                    Success = $false
                    Result = $null
                    Error = $_.Exception.Message
                }
                $this.Logger.LogError("Failed to execute on $serverName`: $($_.Exception.Message)", "Session Execution")
                $this.UserInteraction.UpdateProgressBar($progressBar, 1, "Failed: $serverName")
            }
        }
        
        $this.UserInteraction.CompleteProgressBar($progressBar)
        return $results
    }
    
    [void]CleanupSession([string]$ServerName) {
        $serverInfo = $this.GetServerInfo($ServerName)
        if ($serverInfo) {
            $this.SessionPool.RemoveSession($serverInfo.Address)
            $this.Logger.LogInfo("Cleaned up session for $ServerName", "Session Management")
        }
    }
    
    [void]CleanupAllSessions() {
        $sessionCount = $this.SessionPool.GetActiveSessionCount()
        $this.SessionPool.CleanupAllSessions()
        $this.Logger.LogInfo("Cleaned up $sessionCount sessions", "Session Management")
        [UserInteraction]::WriteActivity("Cleaned up $sessionCount PowerShell sessions", 'info')
    }
    
    [void]CleanupIdleSessions() {
        $originalCount = $this.SessionPool.GetActiveSessionCount()
        $this.SessionPool.CleanupIdleSessions()
        $newCount = $this.SessionPool.GetActiveSessionCount()
        $cleanedUp = $originalCount - $newCount
        
        if ($cleanedUp -gt 0) {
            $this.Logger.LogInfo("Cleaned up $cleanedUp idle sessions", "Session Management")
        }
    }
    
    [hashtable]GetSessionStatistics() {
        return @{
            ActiveSessions = $this.SessionPool.GetActiveSessionCount()
            CachedServers = $this.ServerCache.Count
            DefaultRetryCount = $this.DefaultRetryCount
            DefaultRetryDelay = $this.DefaultRetryDelaySeconds
            ConnectionTimeout = $this.DefaultConnectionTimeoutSeconds
        }
    }
    
    [object[]]GetServersWithTasks([string]$ServiceAccount = $null) {
        $serversWithTasks = @()
        
        foreach ($serverName in $this.ServerCache.Keys) {
            $serverInfo = $this.ServerCache[$serverName]
            if ($serverInfo.Tasks.Count -gt 0) {
                $serversWithTasks += @{
                    ServerName = $serverName
                    ServerInfo = $serverInfo
                    TaskCount = $serverInfo.Tasks.Count
                }
            }
        }
        
        return $serversWithTasks
    }
    
    [object[]]GetServersWithPorts() {
        $serversWithPorts = @()
        
        foreach ($serverName in $this.ServerCache.Keys) {
            $serverInfo = $this.ServerCache[$serverName]
            if ($serverInfo.Ports.Count -gt 0) {
                $serversWithPorts += @{
                    ServerName = $serverName
                    ServerInfo = $serverInfo
                    PortCount = $serverInfo.Ports.Count
                }
            }
        }
        
        return $serversWithPorts
    }
}

# Global SessionHelper instance
$Global:SessionHelper = $null

function Initialize-SessionHelper {
    param([object]$Config)
    $Global:SessionHelper = [SessionHelper]::new($Config)
}

function Get-SessionHelper {
    if (-not $Global:SessionHelper) {
        throw "SessionHelper not initialized. Call Initialize-SessionHelper first."
    }
    return $Global:SessionHelper
}

# Convenience functions for common operations
function New-ManagedSession {
    param(
        [Parameter(Mandatory)]
        [string]$ServerName,
        [bool]$UsePool = $true
    )
    $sessionHelper = Get-SessionHelper
    return $sessionHelper.CreateSession($ServerName, $UsePool)
}

function New-MultipleManagedSessions {
    param(
        [Parameter(Mandatory)]
        [string[]]$ServerNames,
        [bool]$UsePool = $true
    )
    $sessionHelper = Get-SessionHelper
    return $sessionHelper.CreateMultipleSessions($ServerNames, $UsePool)
}

function Invoke-ManagedSessionCommand {
    param(
        [Parameter(Mandatory)]
        [object]$Session,
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [Parameter(Mandatory)]
        [string]$Description,
        [string]$CommandType = $null,
        [object[]]$ArgumentList = @()
    )
    $sessionHelper = Get-SessionHelper
    
    if ($CommandType) {
        return $sessionHelper.ExecuteOnSession($Session, $ScriptBlock, $Description, $CommandType, $ArgumentList)
    } else {
        return $sessionHelper.ExecuteOnSession($Session, $ScriptBlock, $Description, $ArgumentList)
    }
}

function Remove-AllManagedSessions {
    $sessionHelper = Get-SessionHelper
    $sessionHelper.CleanupAllSessions()
}

function Get-ManagedSessionStatistics {
    $sessionHelper = Get-SessionHelper
    return $sessionHelper.GetSessionStatistics()
}

Export-ModuleMember -Function Initialize-SessionHelper, Get-SessionHelper, New-ManagedSession, New-MultipleManagedSessions, Invoke-ManagedSessionCommand, Remove-AllManagedSessions, Get-ManagedSessionStatistics 