class Logger {
    [string]$LogFilePath
    [string]$UserName
    [datetime]$SessionStart
    [bool]$IsActive
    [object]$Config
    static [Logger]$Instance
    static [object]$Lock = [object]::new()

    Logger([object]$config) {
        $this.Config = $config
        $this.UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $this.SessionStart = Get-Date
        $this.IsActive = $true
        
        # Create logs directory if it doesn't exist
        $logsDir = if ($this.Config.log_folder) { 
            Join-Path $PSScriptRoot "..\$($this.Config.log_folder)" 
        } else { 
            Join-Path $PSScriptRoot "..\logs" 
        }
        
        if (-not (Test-Path $logsDir)) {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        }
        
        # Create log file with user name and timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $safeUserName = $this.UserName -replace '[\\/:*?"<>|]', '_'
        $this.LogFilePath = Join-Path $logsDir "audit_${safeUserName}_${timestamp}.log"
        
        # Initialize log file with session header
        $this.WriteLog("=== SESSION START ===", "INFO")
        $this.WriteLog("User: $($this.UserName)", "INFO")
        $this.WriteLog("Session Start: $($this.SessionStart)", "INFO")
        $this.WriteLog("Log File: $($this.LogFilePath)", "INFO")
        $this.WriteLog("", "INFO")
    }

    static [Logger]GetInstance() {
        if (-not [Logger]::Instance) {
            throw "Logger not initialized. Call Initialize-Logger with configuration first."
        }
        return [Logger]::Instance
    }

    static [Logger]Initialize([object]$Config) {
        if (-not [Logger]::Instance) {
            [Logger]::Instance = [Logger]::new($Config)
        }
        return [Logger]::Instance
    }

    static [void]Reset() {
        if ([Logger]::Instance) {
            [Logger]::Instance.CloseSession()
            [Logger]::Instance = $null
        }
    }

    [void]WriteLog([string]$Message, [string]$Level = "INFO") {
        if (-not $this.IsActive) { return }
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        
        try {
            Add-Content -Path $this.LogFilePath -Value $logEntry -ErrorAction Stop
        } catch {
            Write-Host "Failed to write to log file: $_" -ForegroundColor Red
        }
    }

    [void]LogUserInput([string]$Input, [string]$Context = "User Input") {
        if ($Input -match "password|passwd|pwd" -or $Input -match "-AsSecureString") {
            $this.WriteLog("$Context - [PASSWORD HIDDEN]", "USER_INPUT")
        } else {
            $this.WriteLog("$Context - $Input", "USER_INPUT")
        }
    }

    [void]LogMenuSelection([string]$Selection, [string]$MenuName) {
        $this.WriteLog("Menu '$MenuName': Selected '$Selection'", "MENU_SELECTION")
    }

    [void]LogAutomationStart([string]$AutomationName) {
        $this.WriteLog("Starting automation: $AutomationName", "AUTOMATION_START")
    }

    [void]LogAutomationEnd([string]$AutomationName, [bool]$Success = $true) {
        $status = if ($Success) { "SUCCESS" } else { "FAILED" }
        $this.WriteLog("Completed automation: $AutomationName - Status: $status", "AUTOMATION_END")
    }

    [void]LogError([string]$ErrorMessage, [string]$Context = "Error") {
        $this.WriteLog("$Context - $ErrorMessage", "ERROR")
    }

    [void]LogWarning([string]$WarningMessage, [string]$Context = "Warning") {
        $this.WriteLog("$Context - $WarningMessage", "WARNING")
    }

    [void]LogInfo([string]$InfoMessage, [string]$Context = "Info") {
        $this.WriteLog("$Context - $InfoMessage", "INFO")
    }

    [void]LogServerOperation([string]$ServerName, [string]$Operation, [string]$Details) {
        $this.WriteLog("Server '$ServerName': $Operation - $Details", "SERVER_OPERATION")
    }

    [void]LogTaskOperation([string]$ServerName, [string]$TaskName, [string]$Operation, [bool]$Success = $true) {
        $status = if ($Success) { "SUCCESS" } else { "FAILED" }
        $this.WriteLog("Task '$TaskName' on '$ServerName': $Operation - $status", "TASK_OPERATION")
    }

    [void]CloseSession() {
        if (-not $this.IsActive) { return }
        
        $sessionEnd = Get-Date
        $duration = $sessionEnd - $this.SessionStart
        
        $this.WriteLog("", "INFO")
        $this.WriteLog("Session End: $sessionEnd", "INFO")
        $this.WriteLog("Session Duration: $($duration.ToString('hh\:mm\:ss'))", "INFO")
        $this.WriteLog("=== SESSION END ===", "INFO")
        
        $this.IsActive = $false
    }
}

# Backward compatibility functions (deprecated - use Logger::GetInstance() instead)
function Initialize-Logger {
    param([object]$Config)
    [Logger]::Initialize($Config) | Out-Null
}

function Get-Logger {
    return [Logger]::GetInstance()
}

Export-ModuleMember -Function Initialize-Logger, Get-Logger 