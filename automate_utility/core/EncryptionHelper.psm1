class EncryptionHelper {
    [string]$Key

    EncryptionHelper([string]$key) {
        $this.Key = $key
    }

    [string] Encrypt([string] $plainText) {
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.KeySize = 256
        $aes.Key = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($this.Key))
        $aes.IV = [byte[]](1..16)
        $encryptor = $aes.CreateEncryptor()
        $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($plainText)
        $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
        return [Convert]::ToBase64String($cipherBytes)
    }

    [string] Decrypt([string] $cipherText) {
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.KeySize = 256
        $aes.Key = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($this.Key))
        $aes.IV = [byte[]](1..16)
        $decryptor = $aes.CreateDecryptor()
        $cipherBytes = [Convert]::FromBase64String($cipherText)
        $plainBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
        return [System.Text.Encoding]::UTF8.GetString($plainBytes)
    }
}

# Global encryption helper instance
$Global:EncryptionHelper = $null

function Initialize-EncryptionHelper {
    param([string]$Key)
    $Global:EncryptionHelper = [EncryptionHelper]::new($Key)
}

function Get-EncryptionHelper {
    if (-not $Global:EncryptionHelper) {
        throw "EncryptionHelper not initialized. Call Initialize-EncryptionHelper first."
    }
    return $Global:EncryptionHelper
}

Export-ModuleMember -Function Initialize-EncryptionHelper, Get-EncryptionHelper