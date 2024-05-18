##
## 04-pipeline - main.tf
##

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.0.0"
    }
    github = {
      source = "integrations/github"
      version = ">= 6.0.0"
    }
  }
  backend "s3" {
    bucket = "grp3-cap2b-terraform"
    key    = "state/remote-state-04-pipeline"
	  region = "us-west-2"
  }
}

provider "aws" {
  region = "us-west-2"
}


##
## Define Credential variables for GitHub and CodePipeline
##
data "aws_secretsmanager_secret_version" "source_creds" {
  secret_id = "${var.group_alias}-tf-secrets"
}

locals {
  cred_data = jsondecode(
    data.aws_secretsmanager_secret_version.source_creds.secret_string
  )
}

locals {
  repo_cred = local.cred_data.github.access_token
}

# ## Define Source Credential for CodeBuild project
# resource "aws_codebuild_source_credential" "code_build_source_cred" {
#   auth_type   = "PERSONAL_ACCESS_TOKEN"
#   server_type = "GITHUB"
#   token       = local.repo_cred
# }


provider "github" {
  token    = local.repo_cred
  owner    = "${var.repo_owner}"
  # base_url = "https://github.com/${var.repo_owner}/" # we have github enterprise
}


##
## Create ECR Repository
##
resource "aws_ecr_repository" "ecr_repo" {
  name                 = "${var.group_alias}-ecr"
  image_tag_mutability = "MUTABLE"
  tags = {
    Name     = "${var.group_alias}-ecr"
    Capstone = "${var.group_alias}"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}


##
## Create CodeBuild Project (CodePipeline will have the webhook)
##

## Create an S3 bucket for the pipeline -- not sure if needed...
resource "aws_s3_bucket" "pipeline_bucket" {
  bucket  = "${var.group_alias}-pipeline-artifacts"
  tags = {
    Name     = "${var.group_alias}-pipeline-artifacts-bucket"
    Capstone = "${var.group_alias}"
    Description = "This bucket is used for ${var.group_alias} pipeline artifacts data"
  }
}


data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "code_build_role" {
  name               = "${var.group_alias}-codebuild-role"
  description        = "Allows CodeBuild to call AWS services on your behalf."
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags = {
    Name     = "${var.group_alias}-codebuild-role"
    Capstone = "${var.group_alias}"
  }
}

data "aws_iam_policy_document" "policy_access" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs",
    ]

    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateNetworkInterfacePermission"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ecs:*"]
    resources = ["*"]
  }

  statement {
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.pipeline_bucket.arn,
      "${aws_s3_bucket.pipeline_bucket.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "code_build_policy" {
  role   = aws_iam_role.code_build_role.name
  policy = data.aws_iam_policy_document.policy_access.json
}

data "aws_iam_policy" "codebuild_power_policy" {
  name = "AmazonEC2ContainerRegistryPowerUser"
}

## Define the ECR Power User Policy attachement
resource "aws_iam_role_policy_attachment" "codebuild_ecr" {
  role       = aws_iam_role.code_build_role.name
  policy_arn = data.aws_iam_policy.codebuild_power_policy.arn
}


## Create the build project
resource "aws_codebuild_project" "build_docker_image" {
  name          = "${var.group_alias}-react-docker-build"
  description   = "Group 3 Capstone 2 React application build in a Docker Image (Terraform)"
  build_timeout = 5
  service_role  = aws_iam_role.code_build_role.arn

  source {
    type = "CODEPIPELINE"
    # type            = "GITHUB"
    # location        = "https://github.com/maddyericksen/capstone2.git"
    # buildspec       = "buildspec.yml"
    # git_clone_depth = 1

    # git_submodules_config {
    #   fetch_submodules = false
    # }
  }

  source_version = "main"

  artifacts {
    type = "CODEPIPELINE"
    # type      = "S3"
    # location  = aws_s3_bucket.build_artifact_bucket.id
    # name      = "build_artifacts"
    # packaging = "ZIP"
    # namespace = "NONE"
  }

  cache {
    type     = "NO_CACHE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  # logs_config {
  #   cloudwatch_logs {
  #     group_name  = "log-group"
  #     stream_name = "log-stream"
  #   }

  #   s3_logs {
  #     status   = "ENABLED"
  #     location = "${aws_s3_bucket.example.id}/build-log"
  #   }
  # }

  # vpc_config {
  #   vpc_id = aws_vpc.example.id

  #   subnets = [
  #     aws_subnet.example1.id,
  #     aws_subnet.example2.id,
  #   ]

  #   security_group_ids = [
  #     aws_security_group.example1.id,
  #     aws_security_group.example2.id,
  #   ]
  # }

  tags = {
    Name     = "${var.group_alias}-react-docker-build"
    Capstone = "${var.group_alias}"
    Environment = "Capstone2"
  }
}


##
## Create the CodePipeline and the webhook to trigger on repo changes
##
resource "aws_codepipeline" "codepipeline" {
  name     = "${var.group_alias}-ecr-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn
  pipeline_type = "V2"
  execution_mode = "QUEUED"
  tags = {
    Name     = "${var.group_alias}-codepipeline"
    Capstone = "${var.group_alias}"
  }

  artifact_store {
    location = aws_s3_bucket.pipeline_bucket.bucket
    type     = "S3"

  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        Repo        = "${var.repo_uri}"
        Branch      = "${var.repo_branch}"
        Owner       = "${var.repo_owner}"
        OAuthToken  = "${local.repo_cred}"
        PollForSourceChanges = false
      }
      # owner            = "AWS"
      # provider         = "CodeStarSourceConnection"
      # configuration = {
      #   ConnectionArn    = aws_codestarconnections_connection.github_connection.arn
      #   FullRepositoryId = "https://github.com/maddyericksen/capstone2.git"
      #   BranchName       = "main"
      # }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.build_docker_image.name
        EnvironmentVariables = jsonencode([
          {
            name  = "AWS_ACCOUNT_ID"
            value = "${var.account_id}"
            type  = "PLAINTEXT"
          },
          {
            name  = "AWS_DEFAULT_REGION"
            value = "${var.region}"
            type  = "PLAINTEXT"
          },
          {
            name  = "IMAGE_REPO_NAME"
            value = "${var.group_alias}-ecr"
            type  = "PLAINTEXT"
          },
          {
            name  = "IMAGE_TAG"
            value = "latest"
            type  = "PLAINTEXT"
          },
          {
            name  = "CONTAINER_NAME"
            value = "react-app"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["BuildArtifact"]
      version         = "1"

      configuration = {
        ClusterName    = "${var.group_alias}-ecs-cluster"
        ServiceName    = "${var.group_alias}-service"
        FileName       = "imagedefinitions.json"
        DeploymentTimeout: 15        
      }
    }
  }
}


resource "aws_codepipeline_webhook" "aws_webhook_to_github" {
  name            = "${var.group_alias}-aws-webhook-github"
  authentication  = "GITHUB_HMAC"
  target_action   = "Source"
  target_pipeline = aws_codepipeline.codepipeline.name
  tags = {
    Name     = "${var.group_alias}-aws-webhook-github"
    Capstone = "${var.group_alias}"
  }

  authentication_configuration {
    secret_token = local.repo_cred
  }

  filter {
    json_path    = "$.ref"
    match_equals = "refs/heads/{Branch}"
  }
}

# Wire the CodePipeline webhook into a GitHub repository.
# resource "github_repository" "github_repo" {
#   name         = "${var.repo_uri}"
#   description  = "${var.group_alias} Sample Application GitHub Repository"
#   homepage_url = "https://github.com/${var.repo_owner}"
#   visibility   = "public"
# }

resource "github_repository_webhook" "github_repo_webhook" {
  repository = "${var.repo_uri}"
  active = true

  configuration {
    url          = aws_codepipeline_webhook.aws_webhook_to_github.url
    content_type = "json"
    insecure_ssl = false
    secret       = local.repo_cred
  }

  events = ["push"]
}


# resource "aws_codestarconnections_connection" "github_connection" {
#   name          = "github-connection"
#   provider_type = "GitHub"
# }

# resource "aws_s3_bucket" "codepipeline_bucket" {
#   bucket = "test-bucket"
# }

# resource "aws_s3_bucket_public_access_block" "codepipeline_bucket_pab" {
#   bucket = aws_s3_bucket.codepipeline_bucket.id

#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
# }

data "aws_iam_policy_document" "pipeline_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name               = "${var.group_alias}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume_role.json
}


data "aws_iam_policy_document" "codepipeline_policy" {
  statement {
    actions = [
      "iam:PassRole"
    ]
    resources = ["*"]
    effect = "Allow"
    condition {
      test = "StringEqualsIfExists"
      variable = "iam:PassedToService"
      values =[
        "cloudformation.amazonaws.com",
        "elasticbeanstalk.amazonaws.com",
        "ec2.amazonaws.com",
        "ecs-tasks.amazonaws.com"
      ]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObjectAcl",
      "s3:PutObject",
    ]

    resources = [
      aws_s3_bucket.pipeline_bucket.arn,
      "${aws_s3_bucket.pipeline_bucket.arn}/*"
    ]
  }

  statement {
    actions = [
      "elasticbeanstalk:*",
      "ec2:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
      "cloudwatch:*",
      "s3:*",
      "sns:*",
      "cloudformation:*",
      "rds:*",
      "sqs:*",
      "ecs:*"
    ]
    resources = ["*"]
    effect = "Allow"
  }
   

  # statement {
  #   effect    = "Allow"
  #   actions   = ["codestar-connections:UseConnection"]
  #   resources = [aws_codestarconnections_connection.github_connection.arn]
  # }

  statement {
    effect = "Allow"

    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name   = "codepipeline_policy"
  role   = aws_iam_role.codepipeline_role.id
  policy = data.aws_iam_policy_document.codepipeline_policy.json
}
