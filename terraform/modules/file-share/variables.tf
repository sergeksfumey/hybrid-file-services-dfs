variable "storage_account_name" {
  description = "Storage account name (globally unique)"
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "replication_type" {
  description = "Storage replication: LRS, ZRS, GRS, GZRS"
  type        = string
  default     = "GRS"
}

variable "file_share_name" {
  type    = string
  default = "corp-file-share"
}

variable "quota_gb" {
  description = "File share quota in GB"
  type        = number
  default     = 5120
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access storage"
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "Subnet IDs allowed to access storage"
  type        = list(string)
  default     = []
}

variable "enable_private_endpoint" {
  description = "Deploy private endpoint for File Share"
  type        = bool
  default     = false
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoint (required if enable_private_endpoint = true)"
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
