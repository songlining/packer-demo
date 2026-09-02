# Builds a minimal Alpine 3.22 AMI from scratch — no bits from any base AMI.
#
# The `source_ami` below is ONLY a throwaway helper instance that does the
# assembly work (apk bootstrap etc). Its disk is discarded (omit_from_artifact);
# the output AMI is built on a blank attached volume, from scratch.
# Rootfs ~150MB, build ~5min total, boots in seconds.

variable "alpine_patch_level" {
  type    = string
  default = "2026-08"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

source "amazon-ebssurrogate" "scratch" {
  region        = var.aws_region
  instance_type = "t3.micro"
  ami_name      = "from-scratch-{{timestamp}}"
  ssh_username  = "ubuntu"
  ssh_pty       = true

  boot_mode                = "legacy-bios" # MBR + grub-bios installed in the script
  ami_virtualization_type  = "hvm"         # required by amazon plugin >= 1.8
  ena_support              = true          # required, t3.micro won't launch without it

  # Helper AMI — contributes nothing to the artifact
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/*ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  # Helper's own root disk — thrown away
  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
    omit_from_artifact    = true
  }

  # Blank volume the new rootfs is built on — this becomes the AMI's root
  launch_block_device_mappings {
    device_name           = "/dev/sdf"
    volume_size           = 2
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Final AMI layout: the blank volume (assembled on /dev/sdf) becomes the AMI root
  ami_root_device {
    device_name           = "/dev/xvda"
    source_device_name    = "/dev/sdf"
    volume_size           = 2
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ami_description = "Alpine 3.22 built from scratch (amazon-ebssurrogate), no base AMI bits"
  tags = {
    patch-level = var.alpine_patch_level
    owner       = "platform-team"
    os          = "alpine-322-fromscratch"
  }
}

build {
  sources = ["source.amazon-ebssurrogate.scratch"]

  provisioner "shell" {
    script          = "${path.root}/scripts/bootstrap-alpine.sh"
    execute_command = "sudo -E bash -c '{{.Path}}'"
  }
}
