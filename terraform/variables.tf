variable "lab_switch_name" {
  description = "Internal Hyper-V switch for the lab network (LAB-NET)."
  type        = string
  default     = "LAB-NET"
}

variable "internet_switch_name" {
  description = "External or NAT-capable switch for web01's uplink NIC."
  type        = string
  default     = "Default Switch"
}

variable "web01_vcpu" {
  description = "vCPU count for lab-web01."
  type        = number
  default     = 7
}

variable "web01_memory_bytes" {
  description = "Startup memory for lab-web01, in bytes."
  type        = number
  default     = 4294967296 # 4 GiB
}

variable "web01_disk_path" {
  description = "Path to the existing VHD/AVHDX of lab-web01. Set in terraform.tfvars."
  type        = string
}

variable "tf01_vcpu" {
  description = "vCPU count for lab-tf01."
  type        = number
  default     = 2
}

variable "tf01_memory_bytes" {
  description = "Startup memory for lab-tf01, in bytes."
  type        = number
  default     = 4294967296 # 4 GiB
}

variable "tf01_disk_path" {
  description = "Where to create the lab-tf01 VHDX. Set in terraform.tfvars."
  type        = string
}

variable "tf01_disk_size_bytes" {
  description = "Size of the lab-tf01 disk, in bytes."
  type        = number
  default     = 21474836480 # 20 GiB
}

variable "ubuntu_iso_path" {
  description = "Path to the Ubuntu Server ISO used to install lab-tf01."
  type        = string
}
