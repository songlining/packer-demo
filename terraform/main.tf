terraform {
  required_version = ">= 1.5.0"

  cloud {
    # ponytail: HCP Terraform does not allow variables in the cloud block — edit this to your org (see GITHUB-SETUP.md step 5)
    organization = "lab-larry"

    workspaces {
      name = "packer-demo"
    }
  }

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

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

provider "aws" {
  region = var.aws_region
}

# Resolves the webapp image from the production channel — no AMI IDs anywhere.
# Auth via HCP_CLIENT_ID / HCP_CLIENT_SECRET (same service principal as Packer).
data "hcp_packer_artifact" "webapp" {
  bucket_name  = "webapp-a"
  channel_name = "production"
  platform     = "aws"
  region       = var.aws_region
}

resource "aws_security_group" "web" {
  name = "golden-image-demo-web"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app" {
  ami                    = data.hcp_packer_artifact.webapp.external_identifier
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web.id]

  tags = {
    Name    = "golden-image-demo"
    image   = "webapp-a"
    channel = "production"
  }
}

output "public_ip" {
  value = aws_instance.app.public_ip
}
