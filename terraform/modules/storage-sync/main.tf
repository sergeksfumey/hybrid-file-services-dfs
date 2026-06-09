# =============================================================================
# Module: storage-sync
# Description: Azure File Sync -- Storage Sync Service and sync group
# =============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
  }
}

resource "azurerm_storage_sync" "main" {
  name                = var.sync_service_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_storage_sync_group" "main" {
  name            = var.sync_group_name
  storage_sync_id = azurerm_storage_sync.main.id
}

resource "azurerm_storage_sync_cloud_endpoint" "main" {
  name                  = "cloud-endpoint"
  storage_sync_group_id = azurerm_storage_sync_group.main.id
  file_share_name       = var.file_share_name
  storage_account_id    = var.storage_account_id
}

# Diagnostic settings for sync health monitoring
resource "azurerm_monitor_diagnostic_setting" "sync_service" {
  name                       = "diag-storage-sync"
  target_resource_id         = azurerm_storage_sync.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "StorageSyncSyncSessionLog" }
  enabled_log { category = "StorageSyncOperationLog" }
  enabled_log { category = "StorageSyncAgentLog" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

output "sync_service_id" {
  value = azurerm_storage_sync.main.id
}

output "sync_group_id" {
  value = azurerm_storage_sync_group.main.id
}
