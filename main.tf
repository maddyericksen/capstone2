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
  key     = ""
  content = "This bucket is used for ${var.group_alias} application data"
  tags = [
    Name     = "${var.group_alias}-data-bucket"
    Capstone = "${var.group_alias}"
  ]
}

##
## Upload the application data to the S3 bucket
##
resource "aws_s3_object" "todos_app_data" {
  bucket = aws_s3_bucket.todos_data_bucket
  key    = "${var.todo_source_file}"
  source = "${var.todo_source_file}"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = filemd5("${var.todo_source_file}")
}

##
## Creating Lambda function
##

## Define a policy document to use for the Role assignment
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

## Define the Lambda execution role
resource "aws_iam_role" "lambda_iam_role" {
  name               = "${var.group_alias}_lambda_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

## Package the Lambda function code into a Zip file
data "archive_file" "lambda_archive_get_todos" {
  type = "zip"
 
  source_file = "${path.module}/lambda_get_todos.py"
  output_path = "${path.module}/lambda_get_todos_payload.zip"
}

resource "aws_s3_object" "lambda_get_todos_src" {
  bucket = aws_s3_bucket.todos_data_bucket.id
 
  key    = "lambda_get_todos.zip"
  source = data.archive_file.lambda_archive_get_todos.output_path
 
  etag = filemd5(data.archive_file.lambda_archive_get_todos.output_path)
}

## Define Lambda function
resource "aws_lambda_function" "lambda_function_gettodos" {
  s3_bucket = aws_s3_object.lambda_get_todos_src.bucket
  s3_key.   = aws_s3_object.lambda_get_todos_src.key
  function_name = "${var.group_alias}-GetTodos"
  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_archive_get_todos.output_base64sha256
 
  role = aws_iam_role.lambda_iam_role.arn

  description = "Lambda function to retrieve the application data for the API Gateway"
  
  tags = [
    Name     = "${var.group_alias}-GetTodos"
    Capstone = "${var.group_alias}"
  ]
}

## Define Lambda function log stream and access
resource "aws_cloudwatch_log_group" "lambda_log_gettodos" {
  name = "/aws/lambda/${aws_lambda_function.lambda_function_gettodos.function_name}"
  retention_in_days = 5
}

data "aws_iam_policy_document" "lambda_logging" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_policy" "lambda_logging" {
  name        = "${var.group_alias}_lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy      = data.aws_iam_policy_document.lambda_logging.json
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}





# API Gateway
#resource "aws_api_gateway_rest_api" "grp3-cap2b-api" {
#  # Lambda proxy integration = False
#
#  triggers = {
#  }
#}