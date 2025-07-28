using module core/AutomationScript.psm1
using module core/UserInteraction.psm1
using module core/Logger.psm1
using module core/DebugHelper.psm1

function Invoke-UpdateMxlsPasswords {
    param([object]$Config, [object]$DebugHelper)
    $logger = [Logger]::GetInstance()
    $ui = [UserInteraction]::GetInstance()
    Clear-Host
    $ui.ShowScriptTitle("Update MXLS Passwords")
    $ui.WriteBlankLine()
    $ui.WriteActivity("Starting MXLS Password Encryption process...", 'info')
    $logger.LogInfo("Starting MXLS Password Encryption process", "Automation")
    $templateServers = $Config.mxls_template_servers
    $mxlsConfig = $Config.mxls_automation
    $serviceAccount = $mxlsConfig.service_account
    $logger.LogInfo("Processing $($templateServers.Count) template servers for service account: $serviceAccount", "Automation")
    $progressBar = $ui.InitializeProgressBar(10, "MXLS Password Encryption Process")
    $ui.WriteActivity("Step 1: Enter new password for $serviceAccount", 'info')
    $newPassword = $ui.ReadVerifiedPassword("Enter the new password for $serviceAccount")
    $logger.LogUserInput("[PASSWORD ENTERED]", "New MXLS Password")
    $ui.UpdateProgressBar($progressBar, 1, "Step 1: Password Entry")
    $primaryServer = $templateServers | Where-Object { $_.name -eq 'phx-epmap-wp006' }
    if (-not $primaryServer) {
        $ui.WriteActivity("Primary server phx-epmap-wp006 not found in configuration!", 'error')
        $logger.LogError("Primary server phx-epmap-wp006 not found in configuration", "Configuration")
        return
    }
    $ui.WriteActivity("Step 2: Processing primary server $($primaryServer.name)...", 'info')
    $logger.LogServerOperation($primaryServer.name, "Primary Processing", "Starting MXLS password update")
    $session = $null
    try {
        $session = $debugHelper.NewPSSessionOrDebug($primaryServer.address, "Creating session to $($primaryServer.name)")
        $logger.LogServerOperation($primaryServer.name, "Session Creation", "SUCCESS")
        $ui.UpdateProgressBar($progressBar, 1, "Step 2: Session Creation")
        $ui.WriteActivity("Step 3: Updating Login.mxl with new password...", 'info')
        $loginPath = Join-Path $mxlsConfig.templates_path $mxlsConfig.login_file
        UpdateLoginMxl $session $loginPath $newPassword $serviceAccount
        $ui.UpdateProgressBar($progressBar, 1, "Step 3: Update Login.mxl")
        $ui.WriteActivity("Step 4: Generating encryption keys...", 'info')
        $generateKeyPath = Join-Path $mxlsConfig.templates_path $mxlsConfig.generate_key_bat
        GenerateEncryptionKeys $session $generateKeyPath
        $ui.UpdateProgressBar($progressBar, 1, "Step 4: Generate Keys")
        $ui.WriteActivity("Step 5: Updating Encrypt Login.bat with public key...", 'info')
        $encryptLoginPath = Join-Path $mxlsConfig.templates_path $mxlsConfig.encrypt_login_bat
        $encryptionKeyPath = Join-Path $mxlsConfig.templates_path $mxlsConfig.encryption_key_file
        $publicKey = GetPublicKey $session $encryptionKeyPath
        UpdateEncryptLoginBat $session $encryptLoginPath $publicKey
        $ui.UpdateProgressBar($progressBar, 1, "Step 5: Update Encrypt Login.bat")
        $ui.WriteActivity("Step 6: Updating Maxl.bat with private key...", 'info')
        $maxlBatPath = Join-Path $mxlsConfig.scripts_path $mxlsConfig.maxl_bat_file
        $privateKey = GetPrivateKey $session $encryptionKeyPath
        UpdateMaxlBat $session $maxlBatPath $privateKey
        $ui.UpdateProgressBar($progressBar, 1, "Step 6: Update Maxl.bat")
        $ui.WriteActivity("Step 7: Generating encrypted Login.mxls...", 'info')
        RunEncryptLoginBat $session $encryptLoginPath
        $ui.UpdateProgressBar($progressBar, 1, "Step 7: Generate Login.mxls")
        $ui.WriteActivity("Step 8: Updating scripts Login.mxls with encryption keys...", 'info')
        $encryptedLoginPath = Join-Path $mxlsConfig.templates_path $mxlsConfig.encrypted_login_file
        $scriptsLoginMxlsPath = Join-Path $mxlsConfig.scripts_path $mxlsConfig.encrypted_login_file
        UpdateScriptsLoginMxls $session $encryptedLoginPath $scriptsLoginMxlsPath
        $ui.UpdateProgressBar($progressBar, 1, "Step 8: Update Scripts Login.mxls")
        $ui.WriteActivity("Step 9: Hiding password in Login.mxl...", 'info')
        HidePasswordInLoginMxl $session $loginPath $serviceAccount
        $ui.UpdateProgressBar($progressBar, 1, "Step 9: Hide Password")
        $ui.WriteActivity("Step 10: Copying files to other template servers...", 'info')
        $otherServers = $templateServers | Where-Object { $_.name -ne 'phx-epmap-wp006' }
        CopyFilesToOtherServers $session $otherServers $mxlsConfig
        $ui.UpdateProgressBar($progressBar, 1, "Step 10: Copy Files")
        $ui.CompleteProgressBar($progressBar)
        $ui.WriteActivity("MXLS Password Encryption completed successfully!", 'info')
        $logger.LogAutomationEnd("Update MXLS Passwords", $true)
    } catch {
        $ui.WriteActivity("Error during MXLS password encryption: $($_.Exception.Message)", 'error')
        $logger.LogError("Error during MXLS password encryption: $($_.Exception.Message)", "Automation")
        $logger.LogAutomationEnd("Update MXLS Passwords", $false)
    } finally {
        if ($session) {
            Remove-PSSession -Session $session
            $logger.LogInfo("Cleaned up PowerShell session for $($primaryServer.name)", "Session Management")
        }
    }
}

function UpdateLoginMxl {
    param([object]$Session, [string]$LoginPath, [System.Security.SecureString]$NewPassword, [string]$ServiceAccount)
    $logger = [Logger]::GetInstance()
    $debugHelper = [DebugHelper]::GetInstance()
    $logger.LogInfo("Updating Login.mxl with new password", "File Operation")
    
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($NewPassword)
    )
    
    $debugHelper.InvokeOrDebug($Session, {
        param($LoginPath, $NewPassword, $ServiceAccount)
        
        # Backup original file
        $backupPath = $LoginPath + ".backup." + (Get-Date -Format "yyyyMMdd_HHmmss")
        Copy-Item -Path $LoginPath -Destination $backupPath
        
        # Read file content
        $content = Get-Content -Path $LoginPath -Raw
        
        # Replace password for the service account
        $pattern = "login\s+$ServiceAccount\s+'[^']*'"
        $replacement = "login $ServiceAccount '$NewPassword'"
        $newContent = $content -replace $pattern, $replacement
        
        # Write updated content
        Set-Content -Path $LoginPath -Value $newContent -NoNewline
        
    }, "Updating Login.mxl with new password", "Set-Content", @($LoginPath, $plainPassword, $ServiceAccount))
}

function GenerateEncryptionKeys {
    param([object]$Session, [string]$GenerateKeyPath)
    $logger = Get-Logger
    $debugHelper = Get-DebugHelper
    $logger.LogInfo("Generating encryption keys", "Key Generation")
    
    $debugHelper.StartProcessOrDebug($GenerateKeyPath, "", "Generating encryption keys")
}

function GetPublicKey {
    param([object]$Session, [string]$KeyPath)
    $logger = Get-Logger
    $debugHelper = Get-DebugHelper
    $logger.LogInfo("Extracting public key from encryption_key.txt", "Key Extraction")
    
    $publicKey = $debugHelper.InvokeOrDebug($Session, {
        param($KeyPath)
        
        $content = Get-Content -Path $KeyPath
        # Extract public key (first line typically)
        $publicKey = $content[0]
        return $publicKey
        
    }, "Extracting public key from encryption_key.txt", "Get-Content", @($KeyPath))
    
    return $publicKey
}

function UpdateEncryptLoginBat {
    param([object]$Session, [string]$EncryptLoginPath, [string]$PublicKey)
    $logger = Get-Logger
    $debugHelper = Get-DebugHelper
    $logger.LogInfo("Updating Encrypt Login.bat with public key", "File Operation")
    
    $debugHelper.InvokeOrDebug($Session, {
        param($EncryptLoginPath, $PublicKey)
        
        # Backup original file
        $backupPath = $EncryptLoginPath + ".backup." + (Get-Date -Format "yyyyMMdd_HHmmss")
        Copy-Item -Path $EncryptLoginPath -Destination $backupPath
        
        # Read file content
        $content = Get-Content -Path $EncryptLoginPath -Raw
        
        # Replace the public key path/placeholder with actual public key
        $pattern = "REPLACE_WITH_PUBLIC_KEY"
        $newContent = $content -replace $pattern, $PublicKey
        
        # Write updated content
        Set-Content -Path $EncryptLoginPath -Value $newContent -NoNewline
        
    }, "Updating Encrypt Login.bat with public key", "Set-Content", @($EncryptLoginPath, $PublicKey))
}

function GetPrivateKey {
    param([object]$Session, [string]$KeyPath)
    $logger = Get-Logger
    $debugHelper = Get-DebugHelper
    $logger.LogInfo("Extracting private key from encryption_key.txt", "Key Extraction")
    
    $privateKey = $debugHelper.InvokeOrDebug($Session, {
        param($KeyPath)
        
        $content = Get-Content -Path $KeyPath
        # Extract private key (second line typically)
        $privateKey = $content[1]
        return $privateKey
        
    }, "Extracting private key from encryption_key.txt", "Get-Content", @($KeyPath))
    
    return $privateKey
}

function UpdateMaxlBat {
    param([object]$Session, [string]$MaxlBatPath, [string]$PrivateKey)
    $logger = Get-Logger
    $debugHelper = Get-DebugHelper
    $logger.LogInfo("Updating Maxl.bat with private key", "File Operation")
    
    $debugHelper.InvokeOrDebug($Session, {
        param($MaxlBatPath, $PrivateKey)
        
        # Backup original file
        $backupPath = $MaxlBatPath + ".backup." + (Get-Date -Format "yyyyMMdd_HHmmss")
        Copy-Item -Path $MaxlBatPath -Destination $backupPath
        
        # Read file content
        $content = Get-Content -Path $MaxlBatPath -Raw
        
        # Replace the private key placeholder with actual private key
        $pattern = "REPLACE_WITH_PRIVATE_KEY"
        $newContent = $content -replace $pattern, $PrivateKey
        
        # Write updated content
        Set-Content -Path $MaxlBatPath -Value $newContent -NoNewline
        
    }, "Updating Maxl.bat with private key", "Set-Content", @($MaxlBatPath, $PrivateKey))
}

function RunEncryptLoginBat {
    param([object]$Session, [string]$EncryptLoginPath)
    $logger = Get-Logger
    $debugHelper = Get-DebugHelper
    $logger.LogInfo("Running Encrypt Login.bat to generate Login.mxls", "File Operation")
    
    $debugHelper.StartProcessOrDebug($EncryptLoginPath, "", "Running Encrypt Login.bat")
}

function UpdateScriptsLoginMxls {
    param([object]$Session, [string]$EncryptedLoginPath, [string]$ScriptsLoginMxlsPath)
    $logger = Get-Logger
    $debugHelper = Get-DebugHelper
    $logger.LogInfo("Updating scripts Login.mxls with encryption keys", "File Operation")
    
    $debugHelper.InvokeOrDebug($Session, {
        param($EncryptedLoginPath, $ScriptsLoginMxlsPath)
        
        # Read the generated Login.mxls from templates
        $encryptedContent = Get-Content -Path $EncryptedLoginPath -Raw
        
        # Extract the two encryption keys from the content
        $keyPattern = '\$key\s+(\d+)'
        $matches = [regex]::Matches($encryptedContent, $keyPattern)
        
        if ($matches.Count -ge 2) {
            $key1 = $matches[0].Groups[1].Value
            $key2 = $matches[1].Groups[1].Value
            
            # Read the scripts Login.mxls
            $scriptsContent = Get-Content -Path $ScriptsLoginMxlsPath -Raw
            
            # Replace the keys in the scripts Login.mxls
            $scriptsContent = $scriptsContent -replace '\$key\s+\d+', "`$key $key1"
            $scriptsContent = $scriptsContent -replace '\$key\s+\d+', "`$key $key2"
            
            # Write updated content
            Set-Content -Path $ScriptsLoginMxlsPath -Value $scriptsContent -NoNewline
        }
        
    }, "Updating scripts Login.mxls with encryption keys", "Set-Content", @($EncryptedLoginPath, $ScriptsLoginMxlsPath))
}

function HidePasswordInLoginMxl {
    param([object]$Session, [string]$LoginPath, [string]$ServiceAccount)
    $logger = [Logger]::GetInstance()
    $debugHelper = [DebugHelper]::GetInstance()
    $logger.LogInfo("Hiding password in Login.mxl", "File Operation")
    
    $debugHelper.InvokeOrDebug($Session, {
        param($LoginPath, $ServiceAccount)
        
        # Read file content
        $content = Get-Content -Path $LoginPath -Raw
        
        # Replace the actual password with 'password'
        $pattern = "login\s+$ServiceAccount\s+'[^']*'"
        $replacement = "login $ServiceAccount 'password'"
        $newContent = $content -replace $pattern, $replacement
        
        # Write updated content
        Set-Content -Path $LoginPath -Value $newContent -NoNewline
        
    }, "Hiding password in Login.mxl", "Set-Content", @($LoginPath, $ServiceAccount))
}

function CopyFilesToOtherServers {
    param([object]$PrimarySession, [array]$OtherServers, [object]$MxlsConfig)
    $logger = [Logger]::GetInstance()
    $debugHelper = [DebugHelper]::GetInstance()
    $logger.LogInfo("Copying files to other template servers", "File Distribution")
    $ui = [UserInteraction]::GetInstance()
    foreach ($server in $OtherServers) {
        $ui.WriteActivity("Copying files to $($server.name)...", 'info')
        $logger.LogServerOperation($server.name, "File Copy", "Starting file distribution")
        
        $serverSession = $null
        try {
            $serverSession = $debugHelper.NewPSSessionOrDebug($server.address, "Creating session to $($server.name)")
            
            # Copy Maxl.bat and Login.mxls from primary server to this server
            $debugHelper.InvokeOrDebug($serverSession, {
                param($ScriptsPath, $MaxlBatFile, $EncryptedLoginFile)
                
                # Backup existing files
                $maxlBatPath = Join-Path $ScriptsPath $MaxlBatFile
                $loginMxlsPath = Join-Path $ScriptsPath $EncryptedLoginFile
                
                if (Test-Path $maxlBatPath) {
                    $backupPath = $maxlBatPath + ".backup." + (Get-Date -Format "yyyyMMdd_HHmmss")
                    Copy-Item -Path $maxlBatPath -Destination $backupPath
                }
                
                if (Test-Path $loginMxlsPath) {
                    $backupPath = $loginMxlsPath + ".backup." + (Get-Date -Format "yyyyMMdd_HHmmss")
                    Copy-Item -Path $loginMxlsPath -Destination $backupPath
                }
                
            }, "Backing up existing files on $($server.name)", "Copy-Item", @($MxlsConfig.scripts_path, $MxlsConfig.maxl_bat_file, $MxlsConfig.encrypted_login_file))
            
            # Copy files from primary server to this server using Invoke-Command
            $debugHelper.InvokeOrDebug($PrimarySession, {
                param($SourceMaxlBat, $SourceLoginMxls, $ServerSession)
                
                Copy-Item -Path $SourceMaxlBat -Destination $SourceMaxlBat -ToSession $ServerSession -Force
                Copy-Item -Path $SourceLoginMxls -Destination $SourceLoginMxls -ToSession $ServerSession -Force
                
            }, "Copying files from primary server to $($server.name)", "Copy-Item", @((Join-Path $MxlsConfig.scripts_path $MxlsConfig.maxl_bat_file), (Join-Path $MxlsConfig.scripts_path $MxlsConfig.encrypted_login_file), $serverSession))
            
            # Backup and copy template files
            $debugHelper.InvokeOrDebug($serverSession, {
                param($TemplatesPath)
                
                # Backup template folder
                $backupPath = $TemplatesPath + ".backup." + (Get-Date -Format "yyyyMMdd_HHmmss")
                if (Test-Path $TemplatesPath) {
                    Copy-Item -Path $TemplatesPath -Destination $backupPath -Recurse
                }
                
            }, "Backing up template folder on $($server.name)", "Copy-Item", @($MxlsConfig.templates_path))
            
            # Copy all template files from primary server
            $debugHelper.InvokeOrDebug($PrimarySession, {
                param($SourceTemplates, $TemplatesPath, $ServerSession)
                
                Copy-Item -Path $SourceTemplates -Destination $TemplatesPath -ToSession $ServerSession -Recurse -Force
                
            }, "Copying template files from primary server to $($server.name)", "Copy-Item", @((Join-Path $MxlsConfig.templates_path "*"), $MxlsConfig.templates_path, $serverSession))
            
            $logger.LogServerOperation($server.name, "File Copy", "SUCCESS")
            $ui.WriteActivity("Successfully copied files to $($server.name)", 'info')
            
        } catch {
            $ui.WriteActivity("Error copying files to $($server.name): $($_.Exception.Message)", 'error')
            $logger.LogError("Error copying files to $($server.name): $($_.Exception.Message)", "File Distribution")
        } finally {
            if ($serverSession) {
                Remove-PSSession -Session $serverSession
            }
        }
    }
} 