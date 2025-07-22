Import-Module powershell-yaml -ErrorAction Stop

class ConfigLoader {
    [object]$Config

    ConfigLoader() {}

    [object] ImportConfig([string]$ConfigPath) {
        try {
            $yamlContent = Get-Content -Path $ConfigPath -Raw
            $parsedConfig = ConvertFrom-Yaml -Yaml $yamlContent
            return $parsedConfig
        } catch {
            Write-Error "Failed to load configuration from $ConfigPath : $_"
            throw
        }
    }

    [object] UpdateDebugSetting([string]$ConfigPath, [bool]$DebugEnabled) {
        try {
            $yamlContent = Get-Content -Path $ConfigPath -Raw
            $debugValue = if ($DebugEnabled) { 'true' } else { 'false' }
            $debugPattern = '(^\s*debug\s*:\s*)(true|false)'
            if ([regex]::IsMatch($yamlContent, $debugPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline)) {
                $newYamlContent = [regex]::Replace($yamlContent, $debugPattern, "`$1$debugValue", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline)
            } else {
                # If no debug line, add it at the top
                $newYamlContent = "debug: $debugValue`n$yamlContent"
            }
            Set-Content -Path $ConfigPath -Value $newYamlContent -NoNewline
            # Reload the configuration
            $reloadedConfig = $this.ImportConfig($ConfigPath)
            return $reloadedConfig
        } catch {
            Write-Error "Failed to update debug setting in $ConfigPath : $_"
            throw
        }
    }
}

# Global ConfigLoader instance
$Global:ConfigLoader = $null

function Initialize-ConfigLoader {
    $Global:ConfigLoader = [ConfigLoader]::new()
}

function Get-ConfigLoader {
    if (-not $Global:ConfigLoader) {
        throw "ConfigLoader not initialized. Call Initialize-ConfigLoader first."
    }
    return $Global:ConfigLoader
}

# Deprecated function wrappers for backward compatibility
function Import-Config {
    param([string]$ConfigPath)
    $loader = Get-ConfigLoader
    return $loader.ImportConfig($ConfigPath)
}

function Update-DebugSetting {
    param([string]$ConfigPath, [bool]$DebugEnabled)
    $loader = Get-ConfigLoader
    return $loader.UpdateDebugSetting($ConfigPath, $DebugEnabled)
}

Export-ModuleMember -Function Initialize-ConfigLoader, Get-ConfigLoader, Import-Config, Update-DebugSetting 