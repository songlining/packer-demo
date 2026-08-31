hcp_packer_registry {
  bucket_name   = "webapp-a"
  description   = "App image layered on the base-os channel parent — one package, full lineage"
  bucket_labels = { owner = "app-team" }
}

# Parent resolved from the registry via the production channel at build time —
# no AMI ID in this template. hcp-packer-artifact is bundled in Packer core.
data "hcp-packer-artifact" "base" {
  bucket_name  = "base-os"
  channel_name = "production"
  platform     = "aws"
  region       = "ap-southeast-2"
}

source "amazon-ebs" "webapp" {
  region        = "ap-southeast-2"
  instance_type = "t3.micro"
  ami_name      = "webapp-a-{{timestamp}}"
  ssh_username  = "ec2-user"
  source_ami    = data.hcp-packer-artifact.base.external_identifier
  tags = {
    owner = "app-team"
    base  = data.hcp-packer-artifact.base.external_identifier
  }
}

build {
  sources = ["source.amazon-ebs.webapp"]

  # CVE scan inside the build — flip --exit-code to 1 to fail the build on findings
  provisioner "shell" {
    inline = [
      "curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin",
      "sudo trivy rootfs --scanners vuln --severity HIGH,CRITICAL --exit-code 0 /",
    ]
  }

  # requires ansible-playbook on the build host (brew install ansible)
  provisioner "ansible" {
    playbook_file   = "${path.root}/playbooks/webapp.yml"
    extra_arguments = ["--extra-vars", "ansible_python_interpreter=/usr/bin/python3 ansible_remote_tmp=/tmp/ansible"]
  }
}
