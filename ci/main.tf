# CI stack — CodeBuild + CodePipeline replacing GitHub Actions (Option B).
# Source stays in GitHub; projects pull via a CodeConnections GitHub App.
# One-time setup: see ci/README.md.
#
# Secrets (HCP_CLIENT_ID / HCP_CLIENT_SECRET / TFE_TOKEN) are NOT managed here —
# they live in one Secrets Manager secret created out-of-band, so no static keys
# ever touch Terraform state.
terraform {
  required_version = ">= 1.5.0"

  cloud {
    organization = "lab-larry"

    workspaces {
      name = "packer-demo-ci"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

locals {
  repo              = "songlining/packer-demo"
  repo_url          = "https://github.com/${local.repo}.git"
  secret_id         = "packer-demo/ci"
  secret_arn_prefix = "arn:aws:secretsmanager:ap-southeast-2:${data.aws_caller_identity.current.account_id}:secret:${local.secret_id}"
}

data "aws_caller_identity" "current" {}

# --- Roles -------------------------------------------------------------------

data "aws_iam_policy_document" "codebuild_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "logs" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["arn:aws:logs:ap-southeast-2:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/packer-demo-*"]
  }
}

resource "aws_iam_role" "validate" {
  name               = "packer-demo-codebuild-validate"
  assume_role_policy = data.aws_iam_policy_document.codebuild_trust.json
}

resource "aws_iam_role_policy" "validate" {
  name   = "logs"
  role   = aws_iam_role.validate.id
  policy = data.aws_iam_policy_document.logs.json
}

# Packer needs EC2 to build AMIs (instances, key pairs, SGs, snapshots).
# Demo-scoped like the old packer-demo-github OIDC role (PowerUser), plus the
# two CI-only extras: read the HCP/TFE secret, cascade-dispatch the build project.
data "aws_iam_policy_document" "build" {
  statement {
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["${local.secret_arn_prefix}-*"]
  }

  statement {
    actions   = ["codebuild:StartBuild"]
    resources = ["arn:aws:codebuild:ap-southeast-2:${data.aws_caller_identity.current.account_id}:project/packer-demo-build"]
  }
}

resource "aws_iam_role" "build" {
  name               = "packer-demo-codebuild-build"
  assume_role_policy = data.aws_iam_policy_document.codebuild_trust.json
}

resource "aws_iam_role_policy" "build_logs" {
  name   = "logs"
  role   = aws_iam_role.build.id
  policy = data.aws_iam_policy_document.logs.json
}

resource "aws_iam_role_policy" "build" {
  name   = "packer-and-cascade"
  role   = aws_iam_role.build.id
  policy = data.aws_iam_policy_document.build.json
}

resource "aws_iam_role" "deploy" {
  name               = "packer-demo-codebuild-deploy"
  assume_role_policy = data.aws_iam_policy_document.codebuild_trust.json
}

resource "aws_iam_role_policy" "deploy_logs" {
  name   = "logs"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.logs.json
}

resource "aws_iam_role_policy" "deploy" {
  name   = "tfe-token"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

data "aws_iam_policy_document" "deploy" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["${local.secret_arn_prefix}-*"]
  }
}

# --- GitHub connection ---------------------------------------------------------

resource "aws_codeconnections_connection" "github" {
  name          = "packer-demo-github"
  provider_type = "GitHub"
}

# --- Projects -------------------------------------------------------------------

resource "aws_codebuild_project" "validate" {
  name         = "packer-demo-validate"
  service_role = aws_iam_role.validate.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
  }

  source {
    type                = "GITHUB"
    location            = local.repo_url
    buildspec           = "buildspec/validate.yml"
    report_build_status = true

    auth {
      type     = "CODECONNECTIONS"
      resource = aws_codeconnections_connection.github.arn
    }
  }
}

resource "aws_codebuild_webhook" "validate" {
  project_name = aws_codebuild_project.validate.name

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PULL_REQUEST_CREATED, PULL_REQUEST_UPDATED"
    }

    filter {
      type    = "FILE_PATH"
      pattern = "packer/**, terraform/**"
    }
  }
}

resource "aws_codebuild_project" "build" {
  name         = "packer-demo-build"
  service_role = aws_iam_role.build.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true # docker.pkr.hcl builds
  }

  source {
    type            = "GITHUB"
    location        = local.repo_url
    buildspec       = "buildspec/build.yml"
    git_clone_depth = 2 # merge-commit detection: git diff HEAD~1

    auth {
      type     = "CODECONNECTIONS"
      resource = aws_codeconnections_connection.github.arn
    }
  }
}

resource "aws_codebuild_webhook" "build" {
  project_name = aws_codebuild_project.build.name

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }

    filter {
      type    = "HEAD_REF"
      pattern = "refs/heads/main"
    }

    filter {
      type    = "FILE_PATH"
      pattern = "packer/**"
    }
  }
}

# --- Pipeline: source -> manual approval -> deploy -------------------------------

resource "aws_s3_bucket" "artifacts" {
  bucket        = "packer-demo-ci-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

data "aws_iam_policy_document" "codepipeline_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "pipeline" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject",
    ]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
    ]
  }

  statement {
    actions   = ["codeconnections:UseConnection"]
    resources = [aws_codeconnections_connection.github.arn]
  }

  statement {
    actions = [
      "codebuild:StartBuild",
      "codebuild:StopBuild",
      "codebuild:BatchGetBuilds",
    ]
    resources = ["arn:aws:codebuild:ap-southeast-2:${data.aws_caller_identity.current.account_id}:project/packer-demo-deploy"]
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "packer-demo-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_trust.json
}

resource "aws_iam_role_policy" "pipeline" {
  name   = "pipeline"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}

resource "aws_codebuild_project" "deploy" {
  name         = "packer-demo-deploy"
  service_role = aws_iam_role.deploy.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec/deploy.yml"
  }
}

resource "aws_codepipeline" "deploy" {
  name     = "packer-demo-deploy"
  role_arn = aws_iam_role.pipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source"]

      configuration = {
        ConnectionArn    = aws_codeconnections_connection.github.arn
        FullRepositoryId = local.repo
        BranchName       = "main"
      }
    }
  }

  stage {
    name = "Approve"

    action {
      name     = "ApproveDeploy"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        CustomData = "Assign the new version to the production channel in HCP Packer first, then approve."
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source"]

      configuration = {
        ProjectName = aws_codebuild_project.deploy.name
      }
    }
  }
}

# --- Outputs ---------------------------------------------------------------------

output "pipeline_url" {
  value = "https://ap-southeast-2.console.aws.amazon.com/codesuite/codepipeline/pipelines/packer-demo-deploy/view"
}

output "connection_status" {
  value       = aws_codeconnections_connection.github.connection_status
  description = "PENDING until the GitHub App is authorized once in the console (see ci/README.md)"
}
