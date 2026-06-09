variable "sync_service_name" {
  description = "Storage Sync Service name"
  type        = string
}

variable "sync_group_name" {
  description = "Sync group name"
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "file_share_name" {
  description = "Azure File Share name to use as cloud endpoint"
  type        = string
}

variable "storage_account_id" {
  description = "Storage account resource ID"
  type        = string
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
