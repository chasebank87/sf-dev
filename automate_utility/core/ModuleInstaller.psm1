function Install-RequiredModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ModuleNames
    )
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
Export-ModuleMember -Function Install-RequiredModules 