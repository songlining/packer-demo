# SAMPLE ONLY — not part of the demo flow.
# Shows the same base-os pattern as an Azure managed image via the azure-arm builder.

packer {
  required_plugins {
    azure = {
      version = ">= 2.0.0"
      source  = "github.com/hashicorp/azure"
    }
  }
}

variable "patch_level" {
  type    = string
  default = "2026-08"
}

source "azure-arm" "base" {
  # Auth via az login / managed identity — no creds in code
  subscription_id = var.subscription_id

  location        = "australiasoutheast"
  vm_size         = "Standard_B2s"
  os_type         = "Linux"
  image_publisher = "Canonical"
  image_offer     = "ubuntu-24_04-lts"
  image_sku       = "server"
  ssh_username    = "azureuser"

  # Build outputs a managed image in the resource group, not a blob
  managed_image_resource_group_name = "rg-packer-images"
  managed_image_name                = "base-os-{{timestamp}}"

  azure_tags = {
    patch-level = var.patch_level
    owner       = "platform-team"
    os          = "ubuntu-2404"
  }
}

variable "subscription_id" {
  type      = string
  sensitive = true
}

build {
  sources = ["source.azure-arm.base"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
    ]
  }
}
