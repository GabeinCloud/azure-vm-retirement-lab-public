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

variable "linux_admin_password" {
  type      = string
  sensitive = true
}

variable "admin_ssh_public_key_path" {
  type    = string
  default = ""
}

variable "enable_public_ips" {
  type    = bool
  default = true
}
