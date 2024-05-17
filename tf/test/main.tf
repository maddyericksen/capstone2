##
## Test - main.tf
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


## Find the Lambda function reference
data "aws_lambda_function" "todos_lambda" {
  function_name = "${var.group_alias}-GetTodos"
}

output "function_arn" {
  value = data.aws_lambda_function.todos_lambda.invoke_arn
}


data "aws_iam_policy" "codebuild_power_policy" {
  name = "AmazonEC2ContainerRegistryPowerUser"
}

output "policy_arn" {
  value = data.aws_iam_policy.codebuild_power_policy.arn
}


# ##
# ## Define Credential variables for GitHub and CodePipeline
# ##
# data "aws_secretsmanager_secret_version" "source_creds" {
#   secret_id = "grp3-cap2b-tf-secrets"
# }

# locals {
#   cred_data = jsondecode(
#     data.aws_secretsmanager_secret_version.source_creds.secret_string
#   )
# }

# output "data1" {
#   value = nonsensitive(local.cred_data)
#   # sensitive = false
# }

# locals {
#   repo_cred = local.cred_data.github.access_token
# }

# output "data2" {
#   value = nonsensitive(local.repo_cred)
#   # sensitive = false
# }
