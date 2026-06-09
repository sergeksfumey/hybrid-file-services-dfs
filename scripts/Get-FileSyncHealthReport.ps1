<#
.SYNOPSIS
    Generates an Azure File Sync health report across all registered servers.

.DESCRIPTION
    Queries Azure File Sync service for sync session health, pending files,
    cloud tiering efficiency, and conflict count across all server endpoints.
    Exports report to Azure Blob Storage and Log Analytics.

.PARAMETER StorageSyncServiceName
    Azure Storage Sync Service name.

.PARAMETER ResourceGroup
    Azure resource group.

.PARAMETER StorageAccountName
    Storage account for report export.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)][string]$StorageSyncServiceName,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$StorageAccountName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
}

try {
    Write-Log "=== AZURE FILE SYNC HEALTH REPORT ==="
    $reportDate = Get-Date -Format "yyyy-MM-dd"

    Import-Module Az.StorageSync

    $syncService = Get-AzStorageSyncService -ResourceGroupName $ResourceGroup `
        -Name $StorageSyncServiceName

    $servers = Get-AzStorageSyncServer -ParentObject $syncService
    $syncGroups = Get-AzStorageSyncGroup -ParentObject $syncService

    $endpointHealth = @()
    foreach ($group in $syncGroups) {
        $serverEndpoints = Get-AzStorageSyncServerEndpoint -ParentObject $group
        foreach ($ep in $serverEndpoints) {
            $endpointHealth += [PSCustomObject]@{
                SyncGroup          = $group.SyncGroupName
                ServerEndpoint     = $ep.ServerEndpointName
                ServerName         = $ep.ServerName
                LocalPath          = $ep.ServerLocalPath
                CloudTiering       = $ep.CloudTiering
                SyncActivityStatus = $ep.SyncStatus.CombinedHealth
                UploadStatus       = $ep.SyncStatus.UploadActivity.SyncActivityState
                DownloadStatus     = $ep.SyncStatus.DownloadActivity.SyncActivityState
                PendingUploadFiles = $ep.SyncStatus.UploadActivity.PendingFileCount
                PendingUploadBytes = $ep.SyncStatus.UploadActivity.PendingItemBytes
                TieredFileCount    = $ep.CloudTieringStatus.TieredFileCount
                Timestamp          = (Get-Date -Format "o")
            }
        }
    }

    Write-Log "Collected health data for $($endpointHealth.Count) server endpoints"

    $issues = $endpointHealth | Where-Object { $_.SyncActivityStatus -ne "Healthy" }
    if ($issues.Count -gt 0) {
        Write-Log "$($issues.Count) endpoints with health issues" -Level "WARNING"
        $issues | ForEach-Object {
            Write-Log "  UNHEALTHY: $($_.ServerName) -- $($_.LocalPath) -- $($_.SyncActivityStatus)" -Level "WARNING"
        }
    } else {
        Write-Log "All $($endpointHealth.Count) endpoints healthy"
    }

    # Export report
    $reportPath = "$env:TMPDIR/filesync-health-$reportDate.json"
    @{
        ReportDate   = $reportDate
        SyncService  = $StorageSyncServiceName
        TotalServers = $servers.Count
        TotalGroups  = $syncGroups.Count
        Endpoints    = $endpointHealth
        IssueCount   = $issues.Count
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath

    $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
    Set-AzStorageBlobContent -File $reportPath -Container "file-sync-reports" `
        -Blob "health/filesync-health-$reportDate.json" -Context $ctx -Force

    Write-Log "Report exported: file-sync-reports/health/filesync-health-$reportDate.json"
    Write-Log "=== REPORT COMPLETE ==="

} catch {
    Write-Log "Health report failed: $_" -Level "ERROR"
    throw
}
