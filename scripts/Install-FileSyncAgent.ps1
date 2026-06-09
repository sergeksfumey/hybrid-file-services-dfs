<#
.SYNOPSIS
    Installs Azure File Sync agent and registers server endpoint.

.DESCRIPTION
    Downloads and installs Azure File Sync agent on a DFS file server.
    Registers the server with Azure Storage Sync Service.
    Creates a server endpoint on the designated Azure File Sync volume.

    CRITICAL: Azure File Sync volume (E:) must be SEPARATE from DFS-R volume (D:)
    Microsoft does not support DFS-R and Azure File Sync on the same volume.

.PARAMETER StorageSyncServiceName
    Azure Storage Sync Service resource name.

.PARAMETER ResourceGroup
    Azure resource group.

.PARAMETER SyncGroupName
    Sync group name.

.PARAMETER LocalPath
    Local path for Azure File Sync server endpoint (MUST be on separate volume from DFS-R)

.NOTES
    Run on each DFS server (FR01FS001, FR01FS002)
    Azure File Sync volume: E:\AzureFileSync (separate from DFS-R on D:)
    Requires: Az PowerShell module, outbound HTTPS to Azure
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)][string]$StorageSyncServiceName,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$SyncGroupName,
    [string]$LocalPath = "E:\AzureFileSync\CorpShares",
    [int]$CloudTieringFreeSpacePercent = 20,
    [int]$TierFilesOlderThanDays = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
}

try {
    Write-Log "=== AZURE FILE SYNC AGENT INSTALLATION ==="
    Write-Log "Server: $env:COMPUTERNAME | Sync path: $LocalPath"
    Write-Log "CRITICAL: Verifying sync path is NOT on DFS-R volume (D:)"

    if ($LocalPath.StartsWith("D:")) {
        throw "Azure File Sync cannot be configured on D: -- this volume is used by DFS-R. Use E: or another separate volume."
    }

    # Create sync path if not exists
    if (-not (Test-Path $LocalPath)) {
        New-Item -Path $LocalPath -ItemType Directory -Force
        Write-Log "Created sync directory: $LocalPath"
    }

    # Download Azure File Sync agent
    Write-Log "Downloading Azure File Sync agent"
    $agentUrl = "https://aka.ms/storagesyncagent/windows"
    $agentPath = "$env:TEMP\StorageSyncAgent.msi"
    Invoke-WebRequest -Uri $agentUrl -OutFile $agentPath -UseBasicParsing

    # Install agent
    Write-Log "Installing Azure File Sync agent"
    $result = Start-Process -FilePath "msiexec.exe" `
        -ArgumentList "/i `"$agentPath`" /l*v `"$env:TEMPilesync-install.log`" /qn AcceptEULA=Yes" `
        -Wait -PassThru

    if ($result.ExitCode -ne 0) {
        throw "File Sync agent installation failed: exit code $($result.ExitCode)"
    }

    Write-Log "Azure File Sync agent installed"

    # Import Az.StorageSync
    Import-Module Az.StorageSync -ErrorAction Stop

    # Register server
    Write-Log "Registering server with Storage Sync Service: $StorageSyncServiceName"
    Register-AzStorageSyncServer -ResourceGroupName $ResourceGroup `
        -StorageSyncServiceName $StorageSyncServiceName

    Write-Log "Server $env:COMPUTERNAME registered"

    # Create server endpoint
    Write-Log "Creating server endpoint: $LocalPath"
    $syncService = Get-AzStorageSyncService -ResourceGroupName $ResourceGroup `
        -Name $StorageSyncServiceName
    $syncGroup = Get-AzStorageSyncGroup -ParentObject $syncService -Name $SyncGroupName
    $server = Get-AzStorageSyncServer -ParentObject $syncService |
        Where-Object { $_.ServerName -eq $env:COMPUTERNAME }

    New-AzStorageSyncServerEndpoint `
        -Name "endpoint-$env:COMPUTERNAME" `
        -SyncGroup $syncGroup `
        -ServerResourceId $server.ResourceId `
        -ServerLocalPath $LocalPath `
        -CloudTiering `
        -VolumeFreeSpacePercent $CloudTieringFreeSpacePercent `
        -TierFilesOlderThanDays $TierFilesOlderThanDays

    Write-Log "=== AZURE FILE SYNC CONFIGURATION COMPLETE ==="
    Write-Log "Server endpoint: $LocalPath"
    Write-Log "Cloud tiering: enabled ($CloudTieringFreeSpacePercent% free space, files older than $TierFilesOlderThanDays days)"
    Write-Log "Initial sync will begin -- monitor health in Azure portal > Storage Sync Services"

} catch {
    Write-Log "File Sync installation failed: $_" -Level "ERROR"
    throw
}
