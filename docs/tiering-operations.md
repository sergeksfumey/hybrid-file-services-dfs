# Cloud Tiering Operations Guide

## Tiering Policy Configuration

Volume Free Space Policy (primary policy):
- Setting: 20% free space minimum
- Behaviour: when volume drops below 20% free, least-recently-accessed files are tiered
- Use case: general storage constraint management

Date Policy (secondary policy):
- Setting: tier files not accessed in 30 days
- Behaviour: files older than 30 days are tiered regardless of volume space
- Use case: compliance archival, cold data management

Both policies can be active simultaneously -- Azure File Sync applies whichever tiers more aggressively.

## Monitoring Tiering Effectiveness

Key metrics in Azure File Sync health dashboard:
- Tiered file count: total files replaced with stubs on-premises
- Tiered file bytes: storage saved by tiering
- Cache hit ratio: % of file accesses served from local cache vs recalled from Azure
- Recall bytes: total data recalled from Azure (high recall = tiering policy too aggressive)

KQL query for tiering metrics -- see kql/file-sync-health.kql

## Pre-Recall for Planned Heavy Use

Before scheduled heavy access to known cold files (e.g. month-end reporting):

    Invoke-AzStorageSyncFileRecall -ServerEndpoint <endpoint-resource-id>

Or recall specific path:

    Invoke-AzStorageSyncFileRecall -ServerEndpoint <endpoint-resource-id> -Path "E:\AzureFileSync\Reports\2024"

This pre-populates local cache before users access the files -- avoiding recall latency during peak use.

## Tiering Troubleshooting

Files not tiering:
1. Check volume free space policy is active
2. Verify files are older than date policy threshold
3. Check file is not excluded from tiering (open handles prevent tiering)
4. Verify Azure File Share has capacity (tiering stops if share is full)

High recall frequency:
1. Review access patterns -- are users frequently accessing same cold files?
2. Adjust date policy threshold (increase days before tiering)
3. Pre-recall hot files before known heavy use periods
4. Consider excluding specific paths from tiering if recall causes unacceptable UX

Tiered file access fails:
1. Check Azure File Share availability
2. Verify storage account firewall permits server IP
3. Check Azure File Sync agent connectivity (outbound HTTPS 443 required)
4. Review sync agent logs: C:\ProgramData\Microsoft\Azure\StorageSync\logs
