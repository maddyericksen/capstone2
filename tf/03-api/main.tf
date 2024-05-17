##
## 03-api - main.tf
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
    key    = "state/remote-state-03-api"
	  region = "us-west-2"
  }
}

provider "aws" {
  region = "us-west-2"
}


##
## Define the API Gateway to call the Lambda function
##

## Find the Lambda function reference for the API invocation
data "aws_lambda_function" "todos_lambda" {
  function_name = "${var.group_alias}-GetTodos"
}

## Define the API
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

resource "aws_api_gateway_method_response" "lambda_todo_api_get_method_resp_200" {
  rest_api_id = aws_api_gateway_rest_api.lambda_todo_api.id
  resource_id = aws_api_gateway_resource.lambda_todo_api_get_todo_resource.id
  http_method = aws_api_gateway_method.lambda_todo_api_get_method.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Content-Type"                = true,
    "method.response.header.Access-Control-Allow-Origin" = true
  }
  depends_on = [aws_api_gateway_method.lambda_todo_api_get_method]
}

resource "aws_api_gateway_method_response" "lambda_todo_api_options_method_resp_200" {
  rest_api_id = aws_api_gateway_rest_api.lambda_todo_api.id
  resource_id = aws_api_gateway_resource.lambda_todo_api_get_todo_resource.id
  http_method = aws_api_gateway_method.lambda_todo_api_options_method.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Content-Type"                 = true,
    "method.response.header.Access-Control-Allow-Origin"  = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Headers" = true
  }
  depends_on = [aws_api_gateway_method.lambda_todo_api_options_method]
}

resource "aws_api_gateway_integration" "lambda_todo_api_get_integration" {
  http_method = aws_api_gateway_method.lambda_todo_api_get_method.http_method
  resource_id = aws_api_gateway_resource.lambda_todo_api_get_todo_resource.id
  rest_api_id = aws_api_gateway_rest_api.lambda_todo_api.id
  integration_http_method = "POST"
  type        = "AWS"
  passthrough_behavior = "WHEN_NO_TEMPLATES"
  uri = data.aws_lambda_function.todos_lambda.invoke_arn
  depends_on = [
    aws_api_gateway_method.lambda_todo_api_get_method
    ]
}

resource "aws_api_gateway_integration" "lambda_todo_api_options_integration" {
  http_method = aws_api_gateway_method.lambda_todo_api_options_method.http_method
  resource_id = aws_api_gateway_resource.lambda_todo_api_get_todo_resource.id
  rest_api_id = aws_api_gateway_rest_api.lambda_todo_api.id
  type        = "MOCK"
  depends_on = [aws_api_gateway_method.lambda_todo_api_options_method]
}

resource "aws_api_gateway_integration_response" "lambda_todo_api_get_integration_resp" {
  rest_api_id = aws_api_gateway_rest_api.lambda_todo_api.id
  resource_id = aws_api_gateway_resource.lambda_todo_api_get_todo_resource.id
  http_method = aws_api_gateway_method.lambda_todo_api_get_method.http_method
  status_code = aws_api_gateway_method_response.lambda_todo_api_get_method_resp_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  depends_on = [
    aws_api_gateway_method.lambda_todo_api_get_method,
    aws_api_gateway_integration.lambda_todo_api_get_integration,
    aws_api_gateway_method_response.lambda_todo_api_get_method_resp_200
    ]
}

resource "aws_api_gateway_integration_response" "lambda_todo_api_options_integration_resp" {
  rest_api_id = aws_api_gateway_rest_api.lambda_todo_api.id
  resource_id = aws_api_gateway_resource.lambda_todo_api_get_todo_resource.id
  http_method = aws_api_gateway_method.lambda_todo_api_options_method.http_method
  status_code = aws_api_gateway_method_response.lambda_todo_api_options_method_resp_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
  }
  depends_on = [
    aws_api_gateway_method.lambda_todo_api_options_method,
    aws_api_gateway_method_response.lambda_todo_api_options_method_resp_200
    ]
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
  depends_on = [aws_api_gateway_integration.lambda_todo_api_get_integration]
}

resource "aws_lambda_permission" "apigw_lambda" {
    statement_id  = "AllowExecutionFromAPIGateway"
    action        = "lambda:InvokeFunction"
    function_name = data.aws_lambda_function.todos_lambda.arn
    principal     = "apigateway.amazonaws.com"
    source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${aws_api_gateway_rest_api.lambda_todo_api.id}/*/${aws_api_gateway_method.lambda_todo_api_get_method.http_method}/*"
}
