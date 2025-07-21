# Salesforce Hyperion Automation Suite

A PowerShell-based automation framework for managing quarterly password changes and MXLS file encryption across multiple Windows servers.

## 🚀 Features

- **Quarterly Password Management**: Automate scheduled task password updates across multiple servers
- **MXLS File Encryption**: Secure MXLS login files with encryption key management
- **Debug Mode**: Safe testing environment that logs commands without execution
- **Comprehensive Logging**: Detailed audit trails for all operations
- **User-Friendly Interface**: Interactive menu system with confirmation prompts
- **Multi-Server Support**: Manage multiple servers from a single interface

## 📁 Project Structure

```
salesforce/
├── core/                          # Core modules and utilities
│   ├── AutomationScript.psm1     # Base automation script class
│   ├── ConfigLoader.psm1         # Configuration loading utilities
│   ├── DebugHelper.psm1          # Debug mode functionality
│   ├── Logger.psm1               # Logging system
│   ├── ModuleInstaller.psm1      # PowerShell module installer
│   └── UserInteraction.psm1      # Menu and user interface
├── scripts/                       # Automation scripts
│   ├── Update-TaskPasswords.psm1 # Scheduled task password updates
│   └── Update-MxlsPasswords.psm1 # MXLS file encryption
├── config/                        # Configuration files
│   └── dev.yaml                  # Development configuration
├── logs/                          # Log files (auto-created)
├── main.ps1                       # Main application entry point
└── README.md                      # This file
```

## 🛠️ Prerequisites

- **PowerShell 5.0+** or **PowerShell Core 6.0+**
- **Windows Server** environment (for target servers)
- **Administrative privileges** on target servers
- **PowerShell Remoting** enabled on target servers

### Required PowerShell Modules

The application will automatically install these modules:
- `psAsciiArt` - For ASCII art display
- `powershell-yaml` - For YAML configuration parsing

## ⚙️ Configuration

### Configuration File: `config/dev.yaml`

```yaml
# Debug mode (set to true for testing)
debug: false

# Service account for password updates
service_account: 'service_account'

# Logging configuration
log_folder: 'logs'

# ASCII art path (optional)
ascii_art_path: 'assets/logo.png'

# Server configurations
servers:
  - name: 'server1'
    address: 'server1.domain.local'
  - name: 'server2'
    address: 'server2.domain.local'

# MXLS Template servers
mxls_template_servers:
  - name: 'server_name'
    address: 'fqdn'
  - name: 'server_name'
    address: 'fqdn'
  - name: 'server_name'
    address: 'fqdn'

# MXLS Automation settings
mxls_automation:
  base_path: 'D:\\Hyperion\\Automation'
  scripts_path: 'D:\\Hyperion\\Automation\\scripts'
  templates_path: 'D:\\Hyperion\\Automation\\scripts\\templates\\Login'
  service_account: 'svc_epmprdadmin'
  login_file: 'Login.mxl'
  encrypted_login_file: 'Login.mxls'
  maxl_bat_file: 'Maxl.bat'
  encrypt_login_bat: 'Encrypt Login.bat'
  generate_key_bat: 'Generate Encrypt Key.bat'
  encryption_key_file: 'encryption_key.txt'
```

## 🚀 Usage

### Starting the Application

```powershell
# Navigate to the project directory
cd salesforce

# Run the main application
.\main.ps1
```

### Main Menu Options

1. **Quarterly Password Change** - Access password management automations
2. **Toggle Debug Mode** - Enable/disable debug mode for safe testing
3. **Exit** - Close the application

### Debug Mode

Debug mode allows you to test automations safely:
- **Commands are logged** but not executed
- **Retrieval commands** (Get-*, Test-*) are allowed to run
- **Modification commands** (Set-*, Copy-*, Start-Process) are blocked
- **Visual feedback** shows what would be executed

To enable debug mode:
1. Select "Toggle Debug Mode" from the main menu
2. Debug status is displayed under the banner
3. Run automations to see what would happen

## 🔧 Automation Scripts

### Update Task Passwords

Updates scheduled task passwords across multiple servers:

1. **Connects** to each configured server
2. **Retrieves** scheduled tasks for the service account
3. **Displays** a summary table of found tasks
4. **Prompts** for new password (with verification)
5. **Updates** passwords for all matching tasks
6. **Reports** success/failure statistics

### Update MXLS Passwords

Manages MXLS file encryption across template servers:

1. **Processes** primary server (phx-epmap-wp006) first
2. **Updates** Login.mxl with new password
3. **Generates** encryption keys
4. **Updates** batch files with keys
5. **Encrypts** Login.mxl to Login.mxls
6. **Distributes** files to other template servers

## 📊 Logging

All operations are logged to the `logs/` directory with:
- **Timestamp** and **user** information
- **Server operations** and **task details**
- **Success/failure** status
- **Error messages** and **stack traces**

### Log Categories

- **Automation** - High-level automation events
- **Server Operation** - Remote server interactions
- **Task Operation** - Individual task operations
- **User Action** - User input and decisions
- **Configuration** - Config changes and loading
- **Debug** - Debug mode operations

## 🛡️ Security Features

- **Secure password input** with verification
- **Session management** with proper cleanup
- **Error handling** with detailed logging
- **Configuration protection** via .gitignore
- **Debug mode** for safe testing

## 🔍 Troubleshooting

### Common Issues

1. **PowerShell Remoting Not Enabled**
   ```powershell
   # Enable PowerShell remoting on target servers
   Enable-PSRemoting -Force
   ```

2. **Module Installation Fails**
   ```powershell
   # Install NuGet provider manually
   Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
   ```

3. **Permission Denied**
   - Ensure running as Administrator
   - Check target server permissions
   - Verify service account exists

### Debug Mode Testing

1. Enable debug mode from main menu
2. Run automations to see what would execute
3. Check logs for detailed operation information
4. Disable debug mode when ready for production

## 📝 Development

### Adding New Automations

1. Create new script in `scripts/` directory
2. Inherit from `AutomationScript` base class
3. Implement the `Run()` method
4. Add menu option in `main.ps1`
5. Update configuration as needed

### Code Style

- Use **PascalCase** for class and method names
- Use **camelCase** for variables
- Include **comprehensive logging**
- Add **error handling** for all operations
- Use **debug helper** for command execution

## 📄 License

This project is for internal use within the organization.

## 🤝 Contributing

1. Not approving pull requests
---

**Note**: This automation suite is designed for enterprise environments. Always test in debug mode before running in production. 