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
  source = "${var.todo_source_file}"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = filemd5("${var.todo_source_file}")
  tags = {
    Name     = "${var.group_alias}-app-data"
    Capstone = "${var.group_alias}"
  }
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
  tags = {
    Name     = "${var.group_alias}-lambda-iam-role"
    Capstone = "${var.group_alias}"
  }
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

## Define the IAM Lambda Logging Policy
resource "aws_iam_policy" "lambda_logging" {
  name        = "${var.group_alias}_lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy      = data.aws_iam_policy_document.lambda_logging.json
  tags = {
    Name     = "${var.group_alias}-lambda-logging-policy"
    Capstone = "${var.group_alias}"
  }
}

## Define the IAM Lambda Lgging Policy attachement
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

##
## Define the API Gateway to call the Lambda function
##
resource "aws_api_gateway_rest_api" "lambda_todo_api" {
  name = "${var.group_alias}-RestAPI"
  description = "Group 3 Capstone2 REST API (Terraform)"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  tags = {
    Name     = "${var.group_alias}-RestAPI"
    Capstone = "${var.group_alias}"
  }
}

resource "aws_api_gateway_resource" "lambda_todo_api_get_todo_resource" {
  parent_id   = aws_api_gateway_rest_api.lambda_todo_api.root_resource_id
  path_part   = "get-todo"
  rest_api_id = aws_api_gateway_rest_api.lambda_todo_api.id
}

resource "aws_api_gateway_method" "lambda_todo_api_get_method" {
  authorization = "NONE"
  http_method   = "GET"
  resource_id   = aws_api_gateway_resource.lambda_todo_api_get_todo_resource.id
  rest_api_id   = aws_api_gateway_rest_api.lambda_todo_api.id
}

resource "aws_api_gateway_method" "lambda_todo_api_options_method" {
  authorization = "NONE"
  http_method   = "OPTIONS"
  resource_id   = aws_api_gateway_resource.lambda_todo_api_get_todo_resource.id
  rest_api_id   = aws_api_gateway_rest_api.lambda_todo_api.id
}

resource "aws_api_gateway_integration" "lambda_todo_api_get_integration" {
  http_method = aws_api_gateway_method.lambda_todo_api_get_method.http_method
  resource_id = aws_api_gateway_resource.lambda_todo_api_get_todo_resource.id
  rest_api_id = aws_api_gateway_rest_api.lambda_todo_api.id
  integration_http_method = "POST"
  type        = "AWS"
  passthrough_behavior = "WHEN_NO_TEMPLATES"
  uri = aws_lambda_function.lambda_function_gettodos.invoke_arn
  ##. arn:aws:lambda:us-west-2:962804699607:function:grp3-cap2b-GetTodos
}

resource "aws_api_gateway_integration" "lambda_todo_api_options_integration" {
  http_method = aws_api_gateway_method.lambda_todo_api_options_method.http_method
  resource_id = aws_api_gateway_resource.lambda_todo_api_get_todo_resource.id
  rest_api_id = aws_api_gateway_rest_api.lambda_todo_api.id
  type        = "MOCK"
}

resource "aws_api_gateway_deployment" "lambda_todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.lambda_todo_api.id
  description = "Lambda Function RestApi Prod Deployment"
  triggers = {
    # NOTE: The configuration below will satisfy ordering considerations,
    #       but not pick up all future REST API changes. More advanced patterns
    #       are possible, such as using the filesha1() function against the
    #       Terraform configuration file(s) or removing the .id references to
    #       calculate a hash against whole resources. Be aware that using whole
    #       resources will show a difference after the initial implementation.
    #       It will stabilize to only change when resources change afterwards.
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.lambda_todo_api_get_todo_resource.id,
      aws_api_gateway_method.lambda_todo_api_get_method.id,
      aws_api_gateway_integration.lambda_todo_api_get_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "lambda_todo_api_stage" {
  deployment_id = aws_api_gateway_deployment.lambda_todo_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.lambda_todo_api.id
  stage_name    = "prod"
  description   = "Lambda Function RestApi Prod Deployment Stage"
  tags = {
    Name     = "${var.group_alias}-RestAPI-Prod-Stage"
    Capstone = "${var.group_alias}"
  }
}