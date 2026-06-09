# =============================================================================
# Module: backup-vault
# Description: Recovery Services Vault for Azure Backup (File Share) + ASR
# =============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
  }
}

resource "azurerm_recovery_services_vault" "main" {
  name                = var.vault_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  soft_delete_enabled = true
  tags                = var.tags
}

# Azure Backup policy for File Share
resource "azurerm_backup_policy_file_share" "daily" {
  name                = "policy-fileshare-daily-30day"
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.main.name

  backup {
    frequency = "Daily"
    time      = "20:00"
  }

  retention_daily {
    count = 30
  }

  retention_weekly {
    count    = 12
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["Last"]
  }
}

# Protect Azure File Share
resource "azurerm_backup_protected_file_share" "main" {
  resource_group_name       = var.resource_group_name
  recovery_vault_name       = azurerm_recovery_services_vault.main.name
  source_storage_account_id = var.storage_account_id
  source_file_share_name    = var.file_share_name
  backup_policy_id          = azurerm_backup_policy_file_share.daily.id
}

output "vault_id" {
  value = azurerm_recovery_services_vault.main.id
}

output "vault_name" {
  value = azurerm_recovery_services_vault.main.name
}

output "file_share_policy_id" {
  value = azurerm_backup_policy_file_share.daily.id
}
