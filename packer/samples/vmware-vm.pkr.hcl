# SAMPLE ONLY — not part of the demo flow.
# Shows the same base-os pattern as a vSphere VM template via the vsphere-iso builder.

packer {
  required_plugins {
    vsphere = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/vsphere"
    }
  }
}

variable "patch_level" {
  type    = string
  default = "2026-08"
}

variable "vsphere_password" {
  type      = string
  sensitive = true
}

source "vsphere-iso" "base" {
  vcenter_server = "vcenter.example.internal"
  username       = "svc-packer@vsphere.local"
  password       = var.vsphere_password
  datacenter     = "DC1"
  cluster        = "cluster-01"
  datastore      = "vsanDatastore"
  folder         = "Templates/packer"
  guest_os_type  = "ubuntu64Guest"

  vm_name              = "base-os-{{timestamp}}"
  cpus                 = 2
  memory               = 4096
  disk_controller_type = ["pvscsi"]
  network_card         = "vmxnet3"
  ssh_username         = "ubuntu"
  ssh_password         = "ubuntu"

  storage {
    disk_size = 20
  }

  iso_urls     = ["https://releases.ubuntu.com/24.04/ubuntu-24.04.2-live-server-amd64.iso"]
  iso_checksum = "file:https://releases.ubuntu.com/24.04/SHA256SUMS"

  # Autoinstall over the serial console — unattended Ubuntu install
  boot_command = [
    "<esc><esc><esc>",
    "linux /casper/vmlinuz --- autoinstall ds='nocloud-net;s=http://{{.HTTPIP}}:{{.HTTPPort}}/'<enter>",
    "initrd /casper/initrd<enter>",
    "boot<enter>",
  ]
  boot_wait      = "5s"
  http_directory = "http"

  # The payoff: end result is a vSphere template, ready to clone
  convert_to_template = true
}

build {
  sources = ["source.vsphere-iso.base"]

  provisioner "shell" {
    execute_command = "echo 'ubuntu' | {{.Vars}} sudo -S -E sh -c '{{.Path}}'"
    inline = [
      "apt-get update",
      "apt-get upgrade -y",
    ]
  }
}
