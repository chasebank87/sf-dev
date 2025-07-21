class AutomationScript {
    [object]$Config
    AutomationScript([object]$config) {
        $this.Config = $config
    }
    [void]Run() {
        throw [System.NotImplementedException]::new('Run() must be implemented by subclass')
    }
} 