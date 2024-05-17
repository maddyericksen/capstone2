##
## 02-lambda - main.tf
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
    key    = "state/remote-state-02-lambda"
	  region = "us-west-2"
  }
}

provider "aws" {
  region = "us-west-2"
}


##
## Create Lambda function
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
  tags = {
    Name     = "${var.group_alias}-lambda-iam-role"
    Capstone = "${var.group_alias}"
  }
}

## Package the Lambda function code into a Zip file
data "archive_file" "lambda_archive_get_todos" {
  type = "zip"
  source_file = "../../lambda/lambda_function.py"
  output_path = "../../lambda/lambda_function_payload.zip"
  # source_file = "${path.module}/lambda/lambda_function.py"
  # output_path = "${path.module}/lambda/lambda_function_payload.zip"
}

resource "aws_s3_object" "lambda_get_todos_src" {
  bucket = "${var.group_alias}-data"
  key    = "lambda_function.zip"
  source = data.archive_file.lambda_archive_get_todos.output_path
  etag = filemd5(data.archive_file.lambda_archive_get_todos.output_path)
  tags = {
    Name     = "${var.group_alias}-lambda-code"
    Capstone = "${var.group_alias}"
  }
}

## Define Lambda function
resource "aws_lambda_function" "lambda_function_gettodos" {
  s3_bucket = aws_s3_object.lambda_get_todos_src.bucket
  s3_key    = aws_s3_object.lambda_get_todos_src.key
  function_name = "${var.group_alias}-GetTodos"
  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_archive_get_todos.output_base64sha256
  role = aws_iam_role.lambda_iam_role.arn
  description = "Lambda function to retrieve the application data for the API Gateway"
  tags = {
    Name     = "${var.group_alias}-GetTodos"
    Capstone = "${var.group_alias}"
  }
}

## Define Lambda function log stream and access
resource "aws_cloudwatch_log_group" "lambda_log_gettodos" {
  name = "/aws/lambda/${aws_lambda_function.lambda_function_gettodos.function_name}"
  retention_in_days = 5
  tags = {
    Name     = "${var.group_alias}-lambda-log-group"
    Capstone = "${var.group_alias}"
  }
}

## Define the IAM Lambda Logging Policy (document method)
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

## Define a policy document to use for the Role assignment
data "aws_iam_policy_document" "lambda_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = ["arn:aws:s3:::*"]
  }
}

## Define the IAM Lambda Logging Policy
resource "aws_iam_policy" "lambda_logging" {
  name        = "${var.group_alias}_lambda_logging_policy"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy      = data.aws_iam_policy_document.lambda_logging.json
  tags = {
    Name     = "${var.group_alias}-lambda-logging-policy"
    Capstone = "${var.group_alias}"
  }
}

## Define the IAM Lambda S3 Policy
resource "aws_iam_policy" "lambda_s3" {
  name        = "${var.group_alias}_lambda_s3_policy"
  description = "IAM policy for S3 access from a lambda"
  policy      = data.aws_iam_policy_document.lambda_s3.json
  tags = {
    Name     = "${var.group_alias}-lambda-s3-policy"
    Capstone = "${var.group_alias}"
  }
}

## Define the IAM Lambda Lgging Policy attachement
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

## Define the IAM Lambda S3 Policy attachement
resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = aws_iam_policy.lambda_s3.arn
}
