terraform {
  required_providers {
    hyperv = {
      source  = "windsorcli/hyperv"
      version = "0.4.0"
    }
  }
}

provider "hyperv" {
  backend = "local"
}

resource "hyperv_vm" "web01" {
  name       = "lab-web01"
  generation = 2

  cpu = {
    count = var.web01_vcpu
  }

  memory = {
    startup_bytes = var.web01_memory_bytes
  }

  network_adapter = [
    {
      name        = "INTERNET-NIC"
      switch_name = var.internet_switch_name
    },
    {
      name        = "LAB-NET-NIC"
      switch_name = var.lab_switch_name
    }
  ]

  hard_disk_drive = [
    {
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 0
      path                = var.web01_disk_path
    }
  ]

  dvd_drive = [
    {
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 1
    }
  ]
}

resource "hyperv_vhd" "tf01_disk" {
  path       = var.tf01_disk_path
  vhd_type   = "dynamic"
  size_bytes = var.tf01_disk_size_bytes
}

resource "hyperv_vm" "tf01" {
  name       = "lab-tf01"
  generation = 2

  secure_boot = false

  cpu = {
    count = var.tf01_vcpu
  }

  memory = {
    startup_bytes = var.tf01_memory_bytes
  }

  network_adapter = [
    {
      name        = "LAB-NET-NIC"
      switch_name = var.lab_switch_name
    }
  ]

  hard_disk_drive = [
    {
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 0
      path                = hyperv_vhd.tf01_disk.path
    }
  ]

  dvd_drive = [
    {
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 1
      iso_path            = var.ubuntu_iso_path
    }
  ]

  boot_order = [
    {
      type                = "dvd_drive"
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 1
    },
    {
      type                = "hard_disk_drive"
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 0
    },
    {
      type = "network_adapter"
      name = "LAB-NET-NIC"
    }
  ]
}
