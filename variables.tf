variable "location" {
  type    = string
  default = "eastus"
}

variable "resource_group_name" {
  type    = string
  default = "rg-aumlab"
}

variable "admin_username" {
  type    = string
  default = "labadmin"
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Set as TF_VAR_admin_password env var - never in a file. Min 12 chars, upper+lower+number+symbol. Avoid double quotes."
}

variable "allowed_rdp_ip" {
  type        = string
  description = "Your public IP in CIDR format - e.g. 1.2.3.4/32"
}

variable "domain_name" {
  type    = string
  default = "aumlab.local"
}

variable "domain_netbios" {
  type    = string
  default = "AUMLAB"
}

variable "patch_window_start" {
  type        = string
  description = "First maintenance window, format 'YYYY-MM-DD hh:mm'. Must be in the future."
  default     = "2026-11-22 02:00"
}
