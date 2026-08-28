terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = ">= 0.81.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

# Resolves the webapp image from the production channel — no AMI IDs anywhere.
# Auth via HCP_CLIENT_ID / HCP_CLIENT_SECRET (same service principal as Packer).
data "hcp_packer_artifact" "webapp" {
  bucket_name  = "webapp-a"
  channel_name = "production"
  platform     = "aws"
  region       = "ap-southeast-2"
}

resource "aws_instance" "app" {
  ami           = data.hcp_packer_artifact.webapp.external_identifier
  instance_type = "t3.micro"

  tags = {
    Name    = "golden-image-demo"
    image   = "webapp-a"
    channel = "production"
  }
}

output "public_ip" {
  value = aws_instance.app.public_ip
}
