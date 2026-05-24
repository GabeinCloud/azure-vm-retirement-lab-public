variable "location" {
  type    = string
  default = "swedencentral"
}

variable "owner" {
  type    = string
  default = "demo"
}

variable "delete_after" {
  type    = string
  default = "2026-12-31"
}

variable "allowed_source_ip" {
  type = string
}

variable "admin_username" {
  type    = string
  default = "demouser"
}

variable "windows_admin_password" {
  type      = string
  sensitive = true
}

variable "enable_public_ips" {
  type    = bool
  default = true
}

variable "enable_ahb_on_windows_lab_vm" {
  type        = bool
  default     = false
  description = "Set true ONLY if you have rights to attest Azure Hybrid Benefit. Default false to avoid accidental compliance issues."
}
