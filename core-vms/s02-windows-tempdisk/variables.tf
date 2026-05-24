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
  type        = string
  description = "CIDR allowed for RDP. Use x.x.x.x/32 for lab; '*' only for throwaway demos."
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
  default = false
}
