Import-Module powershell-yaml -ErrorAction Stop
function Import-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )
    
    try {
        $yamlContent = Get-Content -Path $ConfigPath -Raw
        $config = ConvertFrom-Yaml -Yaml $yamlContent
        return $config
    } catch {
        Write-Error "Failed to load configuration from $ConfigPath : $_"
        throw
    }
}

function Update-DebugSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,
        [Parameter(Mandatory)]
        [bool]$DebugEnabled
    )
    
    try {
        $yamlContent = Get-Content -Path $ConfigPath -Raw
        $config = ConvertFrom-Yaml -Yaml $yamlContent
        
        # Update the debug setting
        $config.debug = $DebugEnabled
        
        # Convert back to YAML and write to file
        $newYamlContent = ConvertTo-Yaml -Data $config
        Set-Content -Path $ConfigPath -Value $newYamlContent -NoNewline
        
        # Reload the configuration
        $reloadedConfig = Import-Config -ConfigPath $ConfigPath
        
        # Reinitialize debug helper with new config
        Initialize-DebugHelper -Config $reloadedConfig
        
        return $reloadedConfig
    } catch {
        Write-Error "Failed to update debug setting in $ConfigPath : $_"
        throw
    }
}

Export-ModuleMember -Function Import-Config, Update-DebugSetting 