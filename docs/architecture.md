# Architecture Notes -- Hybrid File Services (DFS + Azure File Sync)

## CRITICAL: DFS-R and Azure File Sync Volume Separation

Microsoft explicitly does not support running DFS-R replication and Azure File Sync on the same volume.
This is the most important architectural constraint for this design.

Volume layout per DFS server (FR01FS001 and FR01FS002):
- C: -- OS volume (Windows Server 2025)
- D: -- DFS-R volume (DFS namespace root, DFS-R replicated content)
- E: -- Azure File Sync volume (File Sync server endpoint, cloud tiering)

The DFS namespace presents both volumes transparently through the namespace path.
Users see: \\corp\shares\department
Resolves to: \\FR01FS001\shares (D:) for DFS-R content
            \\FR01FS001\filesync (E:) for cloud-sync content

## DFS Namespace Design

Namespace type: Domain-based (recommended -- supported by multiple servers)
Namespace path: \\corp.local\shares
Namespace servers: FR01FS001, FR01FS002 (both registered as namespace servers)
Site costing: configured to prefer nearest server to minimise WAN traversal

DFS folder targets:
- \\corp.local\shares\general --> \\FR01FS001\shares\general + \\FR01FS002\shares\general
- \\corp.local\shares\projects --> \\FR01FS001\shares\projects + \\FR01FS002\shares\projects
- \\corp.local\shares\archive --> \\FR01FS001\filesync\archive (Azure File Sync tiered)

## Azure File Sync Configuration

Storage Sync Service: sss-corp-file-sync-prod (westeurope)
Sync group: sg-corp-file-share
Cloud endpoint: corp-file-share (Azure File Share)
Server endpoints:
- FR01FS001: E:\AzureFileSync\CorpShares
- FR01FS002: E:\AzureFileSync\CorpShares

Cloud tiering policy:
- Volume free space: 20% minimum (tier when volume drops below 20% free)
- Date policy: tier files not accessed in 30 days
- Both policies active simultaneously -- most restrictive applies

Tiering recall:
- Tiered files: transparent recall on access (slight latency for first access)
- Pre-recall hot files before planned heavy use: Invoke-AzStorageSyncFileRecall
- Monitor recall frequency: File Sync health dashboard > Cloud Tiering section

## Azure File Share Configuration

Storage account: Standard tier, GRS replication
File share: corp-file-share, 5 TiB quota (expandable)
Protocol: SMB 3.x (3.0 and 3.1.1 enabled)
Encryption in transit: AES-256-GCM channel encryption required
Authentication: Azure AD DS (for cloud-native access) + NTFS permissions (sync'd)

Storage account firewall:
- Default action: Deny
- Allowed: on-premises branch office IP ranges
- Allowed: Azure File Sync service endpoints (AzureServices bypass)
- Private endpoint: optional (requires DNS conditional forwarder on-premises)

## Snapshot Policy

Snapshot schedule:
- Hourly: 24 snapshots retained (last 24 hours)
- Daily: 30 snapshots retained (last 30 days)
- Weekly: 12 snapshots retained (last 12 weeks)

Snapshot restore:
1. Azure portal > Storage Account > File shares > corp-file-share > Snapshots
2. Browse snapshot at desired point in time
3. Find file/folder, click Restore
4. Restore in place (overwrites current) or to new location
5. Time to restore: seconds to minutes depending on file size

## Conflict Resolution Process

When Azure File Sync creates a conflict file:
1. Original filename: document.docx (most recently modified version)
2. Conflict filename: document-FR01FS001-2024-01-15T14-30-00Z.docx

Resolution steps:
1. Open conflict report: Azure portal > Storage Sync > Sync Groups > Conflict report
2. Identify conflicting files
3. Compare conflict and original versions
4. Determine which version to keep
5. Delete the version to discard
6. Rename correct version to original name if needed
7. Document resolution in change log
