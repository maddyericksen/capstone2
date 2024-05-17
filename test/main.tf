##
## main.tf
##

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.0.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}


##
## Define Credential variables for GitHub and CodePipeline
##
data "aws_secretsmanager_secret_version" "source_creds" {
  secret_id = "grp3-cap2b-tf-secrets"
}

locals {
  cred_data = jsondecode(
    data.aws_secretsmanager_secret_version.source_creds.secret_string
  )
}

output "data1" {
  value = nonsensitive(local.cred_data)
  # sensitive = false
}

locals {
  repo_cred = local.cred_data.github.access_token
}

output "data2" {
  value = nonsensitive(local.repo_cred)
  # sensitive = false
}
