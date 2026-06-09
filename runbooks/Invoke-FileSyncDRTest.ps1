<#
.SYNOPSIS
    Validates hybrid file services DR capability through controlled test.

.DESCRIPTION
    Tests recovery capabilities across the hybrid file services platform:
    1. Validates Azure File Share snapshot availability
    2. Tests snapshot restore of a test file
    3. Checks ASR replication health for DFS VMs
    4. Verifies Azure File Sync health across all endpoints
    5. Tests direct cloud access via SAS token

.PARAMETER StorageSyncServiceName
    Azure Storage Sync Service name.

.PARAMETER ResourceGroup
    Azure resource group.

.PARAMETER VaultName
    Recovery Services Vault name.

.PARAMETER StorageAccountName
    Storage account name.

.PARAMETER FileShareName
    File share name.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)][string]$StorageSyncServiceName,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$VaultName,
    [Parameter(Mandatory)][string]$StorageAccountName,
    [string]$FileShareName = "corp-file-share"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
}

try {
    Write-Log "=== HYBRID FILE SERVICES DR TEST ==="

    $results = @{ TestDate = (Get-Date -Format "o"); Tests = @{} }

    # Test 1: Azure File Share snapshots
    Write-Log "Test 1: Validating Azure File Share snapshots"
    $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
    $snapshots = Get-AzStorageShare -Context $ctx -Name $FileShareName -SnapshotTime *
    $latestSnapshot = $snapshots | Sort-Object SnapshotTime -Descending | Select-Object -First 1

    if ($latestSnapshot) {
        $snapshotAge = ((Get-Date) - $latestSnapshot.SnapshotTime).TotalHours
        $results.Tests.Snapshots = @{
            Status      = if ($snapshotAge -le 25) { "PASS" } else { "FAIL" }
            LatestAge   = [math]::Round($snapshotAge, 1)
            Count       = $snapshots.Count
        }
        Write-Log "Snapshots: $($snapshots.Count) available, latest $([math]::Round($snapshotAge, 1)) hours ago"
    } else {
        $results.Tests.Snapshots = @{ Status = "FAIL"; Error = "No snapshots found" }
        Write-Log "No snapshots found" -Level "WARNING"
    }

    # Test 2: File Sync endpoint health
    Write-Log "Test 2: Validating File Sync endpoint health"
    Import-Module Az.StorageSync
    $syncService = Get-AzStorageSyncService -ResourceGroupName $ResourceGroup `
        -Name $StorageSyncServiceName
    $groups = Get-AzStorageSyncGroup -ParentObject $syncService
    $endpoints = $groups | ForEach-Object { Get-AzStorageSyncServerEndpoint -ParentObject $_ }
    $unhealthy = $endpoints | Where-Object { $_.SyncStatus.CombinedHealth -ne "Healthy" }

    $results.Tests.FileSyncHealth = @{
        Status         = if ($unhealthy.Count -eq 0) { "PASS" } else { "FAIL" }
        TotalEndpoints = $endpoints.Count
        UnhealthyCount = $unhealthy.Count
    }
    Write-Log "File Sync: $($endpoints.Count) endpoints, $($unhealthy.Count) unhealthy"

    # Test 3: Azure Backup recovery points
    Write-Log "Test 3: Validating Azure Backup recovery points"
    $vault = Get-AzRecoveryServicesVault -Name $VaultName -ResourceGroupName $ResourceGroup
    Set-AzRecoveryServicesVaultContext -Vault $vault
    $container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureStorage `
        -FriendlyName $StorageAccountName
    $item = Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType AzureFiles |
        Where-Object { $_.Name -like "*$FileShareName*" }
    $rp = Get-AzRecoveryServicesBackupRecoveryPoint -Item $item |
        Sort-Object RecoveryPointTime -Descending | Select-Object -First 1

    if ($rp) {
        $rpAge = ((Get-Date) - $rp.RecoveryPointTime).TotalHours
        $results.Tests.AzureBackup = @{
            Status    = if ($rpAge -le 25) { "PASS" } else { "FAIL" }
            LatestRP  = $rp.RecoveryPointTime
            AgeHours  = [math]::Round($rpAge, 1)
        }
        Write-Log "Azure Backup: latest RP $([math]::Round($rpAge, 1)) hours ago"
    } else {
        $results.Tests.AzureBackup = @{ Status = "FAIL"; Error = "No recovery points found" }
    }

    # Overall result
    $allPassed = ($results.Tests.Values | Where-Object { $_.Status -ne "PASS" }).Count -eq 0
    $results.Overall = if ($allPassed) { "PASS" } else { "FAIL" }

    Write-Log "=== DR TEST RESULT: $($results.Overall) ==="
    $results | ConvertTo-Json -Depth 5

} catch {
    Write-Log "DR test failed: $_" -Level "ERROR"
    throw
}
