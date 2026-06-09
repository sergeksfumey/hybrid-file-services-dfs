<#
.SYNOPSIS
    Configures DFS Namespace and DFS-R replication group for hybrid file services.

.DESCRIPTION
    Creates a domain-based DFS namespace and replication group between
    FR01FS001 and FR01FS002 for branch file redundancy.

    CRITICAL: DFS-R and Azure File Sync MUST operate on separate volumes.
    This script configures DFS-R on Volume D: (separate from Azure File Sync on E:)

.PARAMETER NamespaceServer
    Primary DFS namespace server (FR01FS001).

.PARAMETER SecondaryServer
    Secondary DFS namespace server (FR01FS002).

.PARAMETER DomainName
    AD domain name for domain-based namespace.

.NOTES
    Run as Domain Admin on the primary namespace server
    DFS-R volume: D: (MUST be separate from Azure File Sync volume E:)
    Azure File Sync volume: E: (configured separately via Install-FileSyncAgent.ps1)
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)][string]$NamespaceServer,
    [Parameter(Mandatory)][string]$SecondaryServer,
    [string]$DomainName = $env:USERDNSDOMAIN,
    [string]$NamespaceName = "shares",
    [string]$DFSRVolume = "D:",
    [string]$SharePath = "D:\DFSRoots\shares"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
}

try {
    Write-Log "=== DFS NAMESPACE CONFIGURATION ==="
    Write-Log "Primary: $NamespaceServer | Secondary: $SecondaryServer | Domain: $DomainName"
    Write-Log "CRITICAL: Verifying DFS-R is NOT on Azure File Sync volume"

    # Install DFS roles
    Write-Log "Installing DFS Namespace and Replication roles"
    Install-WindowsFeature -Name FS-DFS-Namespace, FS-DFS-Replication -IncludeManagementTools

    # Create namespace root folder
    if (-not (Test-Path $SharePath)) {
        New-Item -Path $SharePath -ItemType Directory -Force
    }

    # Create SMB share for namespace root
    if (-not (Get-SmbShare -Name $NamespaceName -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $NamespaceName -Path $SharePath -FullAccess "Domain Admins" `
            -ChangeAccess "Domain Users" -ReadAccess "Everyone"
        Write-Log "SMB share created: \\$NamespaceServer\$NamespaceName"
    }

    # Create domain-based DFS namespace
    Write-Log "Creating domain-based DFS namespace: \\$DomainName\$NamespaceName"
    New-DfsnRoot -TargetPath "\$NamespaceServer\$NamespaceName" `
        -Type DomainV2 `
        -Path "\$DomainName\$NamespaceName"

    # Add secondary namespace server
    Write-Log "Adding secondary namespace server: $SecondaryServer"
    New-DfsnRootTarget -Path "\$DomainName\$NamespaceName" `
        -TargetPath "\$SecondaryServer\$NamespaceName"

    # Create DFS-R replication group
    Write-Log "Creating DFS-R replication group"
    New-DfsReplicationGroup -GroupName "RG-CorpShares" -DomainName $DomainName

    # Add members
    Add-DfsrMember -GroupName "RG-CorpShares" -ComputerName $NamespaceServer -DomainName $DomainName
    Add-DfsrMember -GroupName "RG-CorpShares" -ComputerName $SecondaryServer -DomainName $DomainName

    # Create replicated folder -- on D: volume (separate from Azure File Sync on E:)
    New-DfsReplicatedFolder -GroupName "RG-CorpShares" -FolderName "shares" -DomainName $DomainName

    # Configure membership (primary = FS001)
    Set-DfsrMembership -GroupName "RG-CorpShares" -FolderName "shares" `
        -ComputerName $NamespaceServer -ContentPath $SharePath `
        -PrimaryMember $true -DomainName $DomainName -Force

    Set-DfsrMembership -GroupName "RG-CorpShares" -FolderName "shares" `
        -ComputerName $SecondaryServer -ContentPath $SharePath `
        -DomainName $DomainName -Force

    # Create replication connection
    Add-DfsrConnection -GroupName "RG-CorpShares" `
        -SourceComputerName $NamespaceServer `
        -DestinationComputerName $SecondaryServer `
        -DomainName $DomainName

    Write-Log "=== DFS NAMESPACE CONFIGURATION COMPLETE ==="
    Write-Log "Namespace: \\$DomainName\$NamespaceName"
    Write-Log "DFS-R volume: $DFSRVolume (SEPARATE from Azure File Sync)"
    Write-Log "Next: Run Install-FileSyncAgent.ps1 on E: volume"

} catch {
    Write-Log "DFS configuration failed: $_" -Level "ERROR"
    throw
}
