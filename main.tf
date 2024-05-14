terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.0.0"
    }
  }
  backend "s3" {
    bucket = "grp3-cap2b-terraform"
    key    = "state/remote-state"
	  region = "us-west-2"
  }
}

provider "aws" {
  region = "us-west-2"
}

##
## Create an S3 bucket to hold the application data.
##
resource "aws_s3_bucket" "todos_data_bucket" {
  bucket  = "${var.group_alias}-data"
  key     = "student.alias"
  content = "This bucket is reserved for ${var.student_alias}"
}

# Creating a lambda function
resource "aws_lambda_function" "grp3-cap2b-gettodos" {
  triggers = {
    
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "grp3-cap2b-api" {
  # Lambda proxy integration = False
}