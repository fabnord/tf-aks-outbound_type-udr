variable "prefix" {
  type    = string
  default = "fnopa"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "admin_user" {
  type = string
}

variable "client_id" {
  type = string
}

variable "client_secret" {
  type = string
}

variable "aad_admin_group" {
  type = string
}

variable "ssh_key" {
  type = string
}
