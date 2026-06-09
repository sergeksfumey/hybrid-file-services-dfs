variable "resource_group_name" {
  type    = string
  default = "rg-hybrid-file-services-prod"
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "storage_account_name" {
  description = "Storage account name (globally unique, 3-24 chars)"
  type        = string
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

variable "vault_name" {
  type = string
}

variable "allowed_ip_ranges" {
  description = "On-premises IP ranges for storage firewall"
  type        = list(string)
  default     = []
}
