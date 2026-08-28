# Same webapp as a container image — the Docker answer for row #5.
# Build: packer build docker.pkr.hcl
# Deploy = push: `docker login`, then uncomment the docker-push post-processor.

packer {
  required_plugins {
    docker = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/docker"
    }
  }
}

variable "tag" {
  type    = string
  default = "1.0.0"
}

source "docker" "webapp" {
  image  = "alpine:3.22"
  commit = true
}

build {
  sources = ["source.docker.webapp"]

  provisioner "shell" {
    inline = [
      "apk add --no-cache nginx",
      "echo '<h1>webapp-a from a golden image</h1>' > /var/lib/nginx/html/index.html",
    ]
  }

  post-processors {
    post-processor "docker-tag" {
      repository = "webapp-a"
      tags       = [var.tag]
    }
    # post-processor "docker-push" {
    #   login = true
    # }
  }
}
