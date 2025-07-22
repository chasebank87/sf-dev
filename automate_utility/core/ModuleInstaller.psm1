class ModuleInstaller {
    ModuleInstaller() {}

    [void] InstallRequiredModules([string[]]$ModuleNames) {
        # Ensure NuGet provider is installed
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Write-Host "Installing NuGet package provider..." -ForegroundColor Yellow
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
        }
        foreach ($module in $ModuleNames) {
            if (-not (Get-Module -ListAvailable -Name $module)) {
                Write-Host "Installing missing module: $module" -ForegroundColor Yellow
                try {
                    Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop -Confirm:$false
                } catch {
                    Write-Host "Failed to install module: $module. Error: $_" -ForegroundColor Red
                    throw
                }
            }
        }
    }
}

# Global ModuleInstaller instance
$Global:ModuleInstaller = $null

function Initialize-ModuleInstaller {
    $Global:ModuleInstaller = [ModuleInstaller]::new()
}

function Get-ModuleInstaller {
    if (-not $Global:ModuleInstaller) {
        throw "ModuleInstaller not initialized. Call Initialize-ModuleInstaller first."
    }
    return $Global:ModuleInstaller
}

# Deprecated function wrapper for backward compatibility
function Install-RequiredModules {
    param([string[]]$ModuleNames)
    $installer = Get-ModuleInstaller
    $installer.InstallRequiredModules($ModuleNames)
}

Export-ModuleMember -Function Initialize-ModuleInstaller, Get-ModuleInstaller, Install-RequiredModules 