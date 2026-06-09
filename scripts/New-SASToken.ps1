<#
.SYNOPSIS
    Generates a scoped SAS token for cloud-only branch access to Azure File Share.

.DESCRIPTION
    Creates a time-limited Shared Access Signature token scoped to the
    Azure File Share with defined permissions for cloud-native branch users.
    Tokens are time-limited and IP-restricted for access governance.

.PARAMETER StorageAccountName
    Storage account name.

.PARAMETER FileShareName
    File share name.

.PARAMETER ValidityHours
    Token validity period in hours. Default: 8 (business day).

.PARAMETER AllowedIpRange
    IP range allowed to use this SAS token.

.PARAMETER Permissions
    Permissions: r=read, w=write, d=delete, l=list. Default: rwdl

.NOTES
    Tokens should be issued per-user or per-application session
    Do NOT create long-lived SAS tokens (> 24 hours for user access)
    Store tokens securely -- do not embed in code or config files
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)][string]$StorageAccountName,
    [string]$FileShareName = "corp-file-share",
    [int]$ValidityHours = 8,
    [Parameter(Mandatory)][string]$AllowedIpRange,
    [string]$Permissions = "rwdl",
    [string]$ResourceGroup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
}

try {
    Write-Log "=== SAS TOKEN GENERATION ==="
    Write-Log "Storage: $StorageAccountName | Share: $FileShareName"
    Write-Log "Validity: $ValidityHours hours | IP: $AllowedIpRange | Permissions: $Permissions"

    $startTime  = (Get-Date).ToUniversalTime()
    $expiryTime = $startTime.AddHours($ValidityHours)

    $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount

    $sasToken = New-AzStorageShareSASToken `
        -Context $ctx `
        -ShareName $FileShareName `
        -Permission $Permissions `
        -StartTime $startTime `
        -ExpiryTime $expiryTime `
        -IPAddressOrRange $AllowedIpRange `
        -Protocol HttpsOnly

    $shareUrl = "\\$StorageAccountName.file.core.windows.net\$FileShareName"
    $mountCmd = "net use Z: `"$shareUrl`" /u:`"AZURE\$StorageAccountName`" `"$sasToken`""

    Write-Log "SAS token generated successfully"
    Write-Log "Valid from: $($startTime.ToString('yyyy-MM-dd HH:mm:ss')) UTC"
    Write-Log "Valid until: $($expiryTime.ToString('yyyy-MM-dd HH:mm:ss')) UTC"
    Write-Log "Permitted IP: $AllowedIpRange"

    Write-Output ""
    Write-Output "=== SHARE MOUNT COMMAND (distribute securely) ==="
    Write-Output $mountCmd
    Write-Output ""
    Write-Output "=== SAS TOKEN (do NOT log or store insecurely) ==="
    Write-Output $sasToken

} catch {
    Write-Log "SAS token generation failed: $_" -Level "ERROR"
    throw
}
