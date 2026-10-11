variable "cp1_ip" {
  description = "Control plane 1 IP"
  default     = "10.70.16.237"
}

variable "cp2_ip" {
  default = "10.70.16.238"
}

variable "cp3_ip" {
  default = "10.70.16.239"
}

variable "worker1_ip" {
  default = "10.70.16.240"
}

variable "worker2_ip" {
  default = "10.70.16.241"
}

variable "vm_user" {
  default = "vm"
}

variable "ssh_key" {
  default = "~/.ssh/id_ed25519"
}
