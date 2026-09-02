variable "patch_level" {
  type    = string
  default = "2026-08"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

hcp_packer_registry {
  bucket_name   = "base-os"
  description   = "Bare-minimal Amazon Linux 2023 base image — value is the metadata chain, not the bytes"
  bucket_labels = { owner = "platform-team", os = "al2023" }
  build_labels  = { "patch-level" = var.patch_level }
}

source "amazon-ebs" "base" {
  region        = var.aws_region
  instance_type = "t3.micro"
  ami_name      = "base-os-{{timestamp}}"
  ssh_username  = "ec2-user"
  tags = {
    patch-level = var.patch_level
    owner       = "platform-team"
    os          = "al2023"
  }

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["137112412989"] # Amazon official
    most_recent = true
  }
}

build {
  sources = ["source.amazon-ebs.base"]

  # ponytail: zero provisioning — vanilla upstream AMI, timestamped + labelled + registered.
  # patch_level var feeds build_labels; changing it produces a distinct registry version.
}
