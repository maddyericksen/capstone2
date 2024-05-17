##
## 01-Setup - main.tf
##

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
    key    = "state/remote-state-01-setup"
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
  tags = {
    Name     = "${var.group_alias}-data-bucket"
    Capstone = "${var.group_alias}"
    Description = "This bucket is used for ${var.group_alias} application data"
  }
}

##
## Upload the application data to the S3 bucket
##
resource "aws_s3_object" "todos_app_data" {
  bucket = aws_s3_bucket.todos_data_bucket.id
  key    = "${var.todo_source_file}"
  source = "../../${var.todo_source_file}"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = filemd5("../../${var.todo_source_file}")
  tags = {
    Name     = "${var.group_alias}-app-data"
    Capstone = "${var.group_alias}"
  }
}
