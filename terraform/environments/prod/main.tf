# =============================================================================
# Environment: Production
# Description: Secure Hybrid File Services -- DFS + Azure File Sync
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate-prod"
    storage_account_name = "stgtfstateprod001"
    container_name       = "tfstate"
    key                  = "hybrid-file-services/prod.tfstate"
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-file-services-prod"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = local.tags
}

module "file_share" {
  source                     = "../../modules/file-share"
  storage_account_name       = var.storage_account_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  replication_type           = "GRS"
  file_share_name            = var.file_share_name
  quota_gb                   = var.quota_gb
  allowed_ip_ranges          = var.allowed_ip_ranges
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags
}

module "storage_sync" {
  source                     = "../../modules/storage-sync"
  sync_service_name          = "sss-corp-file-sync-prod"
  sync_group_name            = "sg-corp-file-share"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  file_share_name            = module.file_share.file_share_name
  storage_account_id         = module.file_share.storage_account_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags
}

module "backup_vault" {
  source              = "../../modules/backup-vault"
  vault_name          = var.vault_name
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  storage_account_id  = module.file_share.storage_account_id
  file_share_name     = module.file_share.file_share_name
  tags                = local.tags
}

locals {
  tags = {
    environment = "prod"
    project     = "hybrid-file-services"
    owner       = "infrastructure-team"
  }
}
