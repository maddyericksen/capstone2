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