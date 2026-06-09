variable "vault_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "storage_account_id" {
  type = string
}

variable "file_share_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
