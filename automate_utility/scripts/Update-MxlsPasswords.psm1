using module ..\core\AutomationScript.psm1
using module ..\core\UserInteraction.psm1
using module ..\core\Logger.psm1
using module ..\core\DebugHelper.psm1

class UpdateMxlsPasswords : AutomationScript {
    UpdateMxlsPasswords([object]$config) : base($config) {}
    [void]Run() {
        $logger = Get-Logger
        $debugHelper = Get-DebugHelper
        
        Write-BlankLine
        Write-Activity "Starting MXLS Password Encryption process..." -type 'info'
        $logger.LogInfo("Starting MXLS Password Encryption process", "Automation")
        
        $templateServers = $this.Config.mxls_template_servers
        $mxlsConfig = $this.Config.mxls_automation
        $serviceAccount = $mxlsConfig.service_account
        
        $logger.LogInfo("Processing $($templateServers.Count) template servers for service account: $serviceAccount", "Automation")
        
        # Step 1: Get the new password from user
        Write-Activity "Step 1: Enter new password for $serviceAccount" -type 'info'
        $newPassword = Read-VerifiedPassword -Prompt "Enter the new password for $serviceAccount"
        $logger.LogUserInput("[PASSWORD ENTERED]", "New MXLS Password")
        
        # Step 2: Process primary server (wp006) first
        $primaryServer = $templateServers | Where-Object { $_.name -eq 'phx-epmap-wp006' }
        if (-not $primaryServer) {
            Write-Activity "Primary server phx-epmap-wp006 not found in configuration!" -type 'error'
            $logger.LogError("Primary server phx-epmap-wp006 not found in configuration", "Configuration")
            return
        }
        
        Write-Activity "Step 2: Processing primary server $($primaryServer.name)..." -type 'info'
        $logger.LogServerOperation($primaryServer.name, "Primary Processing", "Starting MXLS password update")
        
        $session = $null
        try {
            $session = $debugHelper.NewPSSessionOrDebug($primaryServer.address, "Creating session to $($primaryServer.name)")
            $logger.LogServerOperation($primaryServer.name, "Session Creation", "SUCCESS")
            
            # Step 3: Update Login.mxl with new password
            Write-Activity "Step 3: Updating Login.mxl with new password..." -type 'info'
            $loginPath = Join-Path $mxlsConfig.templates_path $mxlsConfig.login_file
            $this.UpdateLoginMxl($session, $loginPath, $newPassword, $serviceAccount)
            
            # Step 4: Generate encryption keys
            Write-Activity "Step 4: Generating encryption keys..." -type 'info'
            $generateKeyPath = Join-Path $mxlsConfig.templates_path $mxlsConfig.generate_key_bat
            $this.GenerateEncryptionKeys($session, $generateKeyPath)
            
            # Step 5: Get public key and update Encrypt Login.bat
            Write-Activity "Step 5: Updating Encrypt Login.bat with public key..." -type 'info'
            $encryptLoginPath = Join-Path $mxlsConfig.templates_path $mxlsConfig.encrypt_login_bat
            $encryptionKeyPath = Join-Path $mxlsConfig.templates_path $mxlsConfig.encryption_key_file
            $publicKey = $this.GetPublicKey($session, $encryptionKeyPath)
            $this.UpdateEncryptLoginBat($session, $encryptLoginPath, $publicKey)
            
            # Step 6: Backup and update Maxl.bat with private key
            Write-Activity "Step 6: Updating Maxl.bat with private key..." -type 'info'
            $maxlBatPath = Join-Path $mxlsConfig.scripts_path $mxlsConfig.maxl_bat_file
            $privateKey = $this.GetPrivateKey($session, $encryptionKeyPath)
            $this.UpdateMaxlBat($session, $maxlBatPath, $privateKey)
            
            # Step 7: Run Encrypt Login.bat to generate Login.mxls
            Write-Activity "Step 7: Generating encrypted Login.mxls..." -type 'info'
            $this.RunEncryptLoginBat($session, $encryptLoginPath)
            
            # Step 8: Extract keys from Login.mxls and update scripts Login.mxls
            Write-Activity "Step 8: Updating scripts Login.mxls with encryption keys..." -type 'info'
            $encryptedLoginPath = Join-Path $mxlsConfig.templates_path $mxlsConfig.encrypted_login_file
            $scriptsLoginMxlsPath = Join-Path $mxlsConfig.scripts_path $mxlsConfig.encrypted_login_file
            $this.UpdateScriptsLoginMxls($session, $encryptedLoginPath, $scriptsLoginMxlsPath)
            
            # Step 9: Hide password in Login.mxl
            Write-Activity "Step 9: Hiding password in Login.mxl..." -type 'info'
            $this.HidePasswordInLoginMxl($session, $loginPath, $serviceAccount)
            
            # Step 10: Copy files to other servers
            Write-Activity "Step 10: Copying files to other template servers..." -type 'info'
            $otherServers = $templateServers | Where-Object { $_.name -ne 'phx-epmap-wp006' }
            $this.CopyFilesToOtherServers($session, $otherServers, $mxlsConfig)
            
            Write-Activity "MXLS Password Encryption completed successfully!" -type 'info'
            $logger.LogAutomationEnd("Update MXLS Passwords", $true)
            
        } catch {
            Write-Activity "Error during MXLS password encryption: $($_.Exception.Message)" -type 'error'
            $logger.LogError("Error during MXLS password encryption: $($_.Exception.Message)", "Automation")
            $logger.LogAutomationEnd("Update MXLS Passwords", $false)
        } finally {
            if ($session) {
                Remove-PSSession -Session $session
                $logger.LogInfo("Cleaned up PowerShell session for $($primaryServer.name)", "Session Management")
            }
        }
    }
    
    [void]UpdateLoginMxl([object]$Session, [string]$LoginPath, [System.Security.SecureString]$NewPassword, [string]$ServiceAccount) {
        $logger = Get-Logger
        $debugHelper = Get-DebugHelper
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
    
    [void]GenerateEncryptionKeys([object]$Session, [string]$GenerateKeyPath) {
        $logger = Get-Logger
        $debugHelper = Get-DebugHelper
        $logger.LogInfo("Generating encryption keys", "Key Generation")
        
        $debugHelper.StartProcessOrDebug($GenerateKeyPath, "", "Generating encryption keys")
    }
    
    [string]GetPublicKey([object]$Session, [string]$KeyPath) {
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
    
    [void]UpdateEncryptLoginBat([object]$Session, [string]$EncryptLoginPath, [string]$PublicKey) {
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
    
    [string]GetPrivateKey([object]$Session, [string]$KeyPath) {
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
    
    [void]UpdateMaxlBat([object]$Session, [string]$MaxlBatPath, [string]$PrivateKey) {
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
    
    [void]RunEncryptLoginBat([object]$Session, [string]$EncryptLoginPath) {
        $logger = Get-Logger
        $debugHelper = Get-DebugHelper
        $logger.LogInfo("Running Encrypt Login.bat to generate Login.mxls", "File Operation")
        
        $debugHelper.StartProcessOrDebug($EncryptLoginPath, "", "Running Encrypt Login.bat")
    }
    
    [void]UpdateScriptsLoginMxls([object]$Session, [string]$EncryptedLoginPath, [string]$ScriptsLoginMxlsPath) {
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
    
    [void]HidePasswordInLoginMxl([object]$Session, [string]$LoginPath, [string]$ServiceAccount) {
        $logger = Get-Logger
        $debugHelper = Get-DebugHelper
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
    
    [void]CopyFilesToOtherServers([object]$PrimarySession, [array]$OtherServers, [object]$MxlsConfig) {
        $logger = Get-Logger
        $debugHelper = Get-DebugHelper
        $logger.LogInfo("Copying files to other template servers", "File Distribution")
        
        foreach ($server in $OtherServers) {
            Write-Activity "Copying files to $($server.name)..." -type 'info'
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
                Write-Activity "Successfully copied files to $($server.name)" -type 'info'
                
            } catch {
                Write-Activity "Error copying files to $($server.name): $($_.Exception.Message)" -type 'error'
                $logger.LogError("Error copying files to $($server.name): $($_.Exception.Message)", "File Distribution")
            } finally {
                if ($serverSession) {
                    Remove-PSSession -Session $serverSession
                }
            }
        }
    }
} 