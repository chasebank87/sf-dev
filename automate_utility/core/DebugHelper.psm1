class DebugHelper {
    [bool]$IsDebugMode
    [object]$Config

    DebugHelper([object]$config) {
        $this.Config = $config
        $this.IsDebugMode = if ($config.debug) { $config.debug } else { $false }
    }

    [bool]IsDebug() {
        return $this.IsDebugMode
    }

    [void]LogCommand([string]$Command, [string]$Description = "") {
        $logger = Get-Logger
        if ($this.IsDebugMode) {
            $message = "DEBUG COMMAND: $Command"
            if ($Description) {
                $message += " - $Description"
            }
            Write-Host $message -ForegroundColor Cyan
            $logger.LogInfo($message, "Debug Command")
        }
    }

    [void]LogFileOperation([string]$Operation, [string]$Source, [string]$Destination = "") {
        $logger = Get-Logger
        if ($this.IsDebugMode) {
            $message = "DEBUG FILE OPERATION: $Operation"
            if ($Destination) {
                $message += " - Source: $Source, Destination: $Destination"
            } else {
                $message += " - Path: $Source"
            }
            Write-Host $message -ForegroundColor Yellow
            $logger.LogInfo($message, "Debug File Operation")
        }
    }

    [void]LogServerOperation([string]$ServerName, [string]$Operation, [string]$Details) {
        $logger = Get-Logger
        if ($this.IsDebugMode) {
            $message = "DEBUG SERVER OPERATION: $ServerName - $Operation - $Details"
            Write-Host $message -ForegroundColor Magenta
            $logger.LogInfo($message, "Debug Server Operation")
        }
    }

    [void]LogPasswordOperation([string]$Operation, [string]$Target) {
        $logger = Get-Logger
        if ($this.IsDebugMode) {
            $message = "DEBUG PASSWORD OPERATION: $Operation - Target: $Target"
            Write-Host $message -ForegroundColor Red
            $logger.LogInfo($message, "Debug Password Operation")
        }
    }

    [bool]ShouldExecuteCommand([string]$CommandType) {
        # Commands that are allowed to run in debug mode (retrieval commands)
        $allowedCommands = @(
            'Get-ScheduledTask',
            'Get-Content',
            'Test-Path',
            'Get-ChildItem',
            'Get-Item',
            'Get-Process',
            'Get-Service',
            'Get-ComputerInfo',
            'Get-PSSession',
            'Get-Module',
            'Get-Command'
        )
        
        foreach ($allowed in $allowedCommands) {
            if ($CommandType -like "*$allowed*") {
                return $true
            }
        }
        
        return -not $this.IsDebugMode
    }

    [void]ExecuteOrDebug([scriptblock]$Command, [string]$Description, [string]$CommandType) {
        if ($this.ShouldExecuteCommand($CommandType)) {
            # Execute the command
            & $Command
        } else {
            # Log what would have been executed
            $this.LogCommand($CommandType, $Description)
        }
    }

    [object]InvokeOrDebug([object]$Session, [scriptblock]$ScriptBlock, [string]$Description, [string]$CommandType, [object[]]$ArgumentList = @()) {
        if ($this.ShouldExecuteCommand($CommandType)) {
            # Execute the command
            if ($ArgumentList.Count -gt 0) {
                return Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
            } else {
                return Invoke-Command -Session $Session -ScriptBlock $ScriptBlock
            }
        } else {
            # Log what would have been executed
            $this.LogCommand($CommandType, $Description)
            return $null
        }
    }

    [void]StartProcessOrDebug([string]$FilePath, [string]$Arguments = "", [string]$Description) {
        if ($this.IsDebugMode) {
            $message = "DEBUG PROCESS: Start-Process -FilePath '$FilePath'"
            if ($Arguments) {
                $message += " -ArgumentList '$Arguments'"
            }
            $message += " - $Description"
            Write-Host $message -ForegroundColor Green
            $this.LogCommand($message, $Description)
        } else {
            if ($Arguments) {
                Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait
            } else {
                Start-Process -FilePath $FilePath -Wait
            }
        }
    }

    [void]CopyItemOrDebug([string]$Source, [string]$Destination, [string]$Description, [hashtable]$Parameters = @{}) {
        if ($this.IsDebugMode) {
            $paramString = ""
            foreach ($key in $Parameters.Keys) {
                $paramString += " -$key '$($Parameters[$key])'"
            }
            $message = "DEBUG COPY: Copy-Item -Path '$Source' -Destination '$Destination'$paramString - $Description"
            Write-Host $message -ForegroundColor Yellow
            $this.LogFileOperation("Copy", $Source, $Destination)
        } else {
            $params = @{
                Path = $Source
                Destination = $Destination
            }
            foreach ($key in $Parameters.Keys) {
                $params[$key] = $Parameters[$key]
            }
            Copy-Item @params
        }
    }

    [void]SetContentOrDebug([string]$Path, [string]$Content, [string]$Description) {
        if ($this.IsDebugMode) {
            $message = "DEBUG SET CONTENT: Set-Content -Path '$Path' - $Description"
            Write-Host $message -ForegroundColor Yellow
            $this.LogFileOperation("Set Content", $Path)
        } else {
            Set-Content -Path $Path -Value $Content -NoNewline
        }
    }

    [object]NewPSSessionOrDebug([string]$ComputerName, [string]$Description) {
        $message = "DEBUG SESSION: New-PSSession -ComputerName '$ComputerName' - $Description"
        Write-Host $message -ForegroundColor Magenta
        $this.LogServerOperation($ComputerName, "Session Creation", "Debug Mode")
        
        # Always create real sessions, even in debug mode
        return New-PSSession -ComputerName $ComputerName -EnableNetworkAccess -ErrorAction Stop
    }
}

# Global debug helper instance
$Global:DebugHelper = $null

function Initialize-DebugHelper {
    param([object]$Config)
    $Global:DebugHelper = [DebugHelper]::new($Config)
}

function Get-DebugHelper {
    if (-not $Global:DebugHelper) {
        throw "DebugHelper not initialized. Call Initialize-DebugHelper first."
    }
    return $Global:DebugHelper
}

Export-ModuleMember -Function Initialize-DebugHelper, Get-DebugHelper 