# =============================================================================
# Module: file-share
# Description: Azure Storage Account and File Share with governance controls
# =============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
  }
}

resource "azurerm_storage_account" "main" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  account_kind             = "StorageV2"

  azure_files_authentication {
    directory_type = "AADDS"
  }

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
  }

  share_properties {
    retention_policy {
      days = 30
    }

    smb {
      versions                        = ["SMB3.0", "SMB3.1.1"]
      authentication_types            = ["NTLMv2", "Kerberos"]
      kerberos_ticket_encryption_type = ["RC4-HMAC", "AES-256"]
      channel_encryption_type         = ["AES-128-CCM", "AES-128-GCM", "AES-256-GCM"]
    }
  }

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  tags = var.tags
}

resource "azurerm_storage_share" "main" {
  name                 = var.file_share_name
  storage_account_name = azurerm_storage_account.main.name
  quota                = var.quota_gb

  enabled_protocol = "SMB"
}

# Snapshot policy -- hourly, daily, weekly
resource "azurerm_storage_management_policy" "snapshots" {
  storage_account_id = azurerm_storage_account.main.id

  rule {
    name    = "file-share-snapshots"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      snapshot {
        delete_after_days_since_creation_greater_than = 30
      }
    }
  }
}

# Diagnostic settings
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "diag-storage-account"
  target_resource_id         = "${azurerm_storage_account.main.id}/fileServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }

  metric {
    category = "Transaction"
    enabled  = true
  }

  metric {
    category = "Capacity"
    enabled  = true
  }
}

# Private endpoint for File Share
resource "azurerm_private_endpoint" "file_share" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "pe-${var.storage_account_name}-file"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${var.storage_account_name}-file"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  tags = var.tags
}

output "storage_account_id" {
  value = azurerm_storage_account.main.id
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "file_share_name" {
  value = azurerm_storage_share.main.name
}

output "primary_file_endpoint" {
  value = azurerm_storage_account.main.primary_file_endpoint
}
