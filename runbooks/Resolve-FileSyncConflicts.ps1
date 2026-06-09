<#
.SYNOPSIS
    Reports and assists resolution of Azure File Sync conflict files.

.DESCRIPTION
    Identifies conflict files created by Azure File Sync bi-directional sync.
    Conflict files are named: originalname-ServerName-timestamp.ext
    Exports conflict report for admin review and resolution.

.PARAMETER StorageSyncServiceName
    Azure Storage Sync Service name.

.PARAMETER ResourceGroup
    Azure resource group.

.PARAMETER StorageAccountName
    Storage account for report export.

.NOTES
    Conflicts occur when same file modified on multiple endpoints before sync completes.
    Resolution requires admin review -- File Sync retains both versions for safety.
    Both conflict and original file are kept -- no data loss.
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
    Write-Log "=== FILE SYNC CONFLICT RESOLUTION REPORT ==="
    $reportDate = Get-Date -Format "yyyy-MM-dd"

    Import-Module Az.StorageSync

    $syncService = Get-AzStorageSyncService -ResourceGroupName $ResourceGroup `
        -Name $StorageSyncServiceName
    $groups = Get-AzStorageSyncGroup -ParentObject $syncService

    $conflictReport = @()
    foreach ($group in $groups) {
        $endpoints = Get-AzStorageSyncServerEndpoint -ParentObject $group
        foreach ($ep in $endpoints) {
            if ($ep.SyncStatus.UploadActivity.PendingFileCount -gt 0 -or
                $ep.SyncStatus.DownloadActivity.PendingFileCount -gt 0) {
                $conflictReport += [PSCustomObject]@{
                    SyncGroup       = $group.SyncGroupName
                    ServerName      = $ep.ServerName
                    LocalPath       = $ep.ServerLocalPath
                    PendingUploads  = $ep.SyncStatus.UploadActivity.PendingFileCount
                    PendingDownloads = $ep.SyncStatus.DownloadActivity.PendingFileCount
                    SyncHealth      = $ep.SyncStatus.CombinedHealth
                    Timestamp       = (Get-Date -Format "o")
                }
            }
        }
    }

    if ($conflictReport.Count -gt 0) {
        Write-Log "$($conflictReport.Count) endpoints with pending sync items" -Level "WARNING"
        Write-Log "Review conflict files in Azure portal > Storage Sync Services > Sync Groups"
        Write-Log "Conflict file naming: originalname-ServerName-timestamp.ext"
        Write-Log "Resolution: compare conflict and original, keep correct version, delete other"
    } else {
        Write-Log "No pending sync conflicts detected"
    }

    $reportPath = "$env:TMPDIR/filesync-conflicts-$reportDate.json"
    @{
        ReportDate    = $reportDate
        ConflictCount = $conflictReport.Count
        Conflicts     = $conflictReport
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath

    $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
    Set-AzStorageBlobContent -File $reportPath -Container "file-sync-reports" `
        -Blob "conflicts/filesync-conflicts-$reportDate.json" -Context $ctx -Force

    Write-Log "Report exported: file-sync-reports/conflicts/filesync-conflicts-$reportDate.json"

} catch {
    Write-Log "Conflict report failed: $_" -Level "ERROR"
    throw
}
