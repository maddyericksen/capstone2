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
    github = {
      source = "integrations/github"
      version = ">= 6.0.0"
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

## Define Source Credential for CodeBuild project
resource "aws_codebuild_source_credential" "code_build_source_cred" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = local.repo_cred
}


provider "github" {
  token    = local.repo_cred
  owner    = "${var.repo_owner}"
  # base_url = "https://github.com/${var.repo_owner}/" # we have github enterprise
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
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda/lambda_function_payload.zip"
}

resource "aws_s3_object" "lambda_get_todos_src" {
  bucket = aws_s3_bucket.todos_data_bucket.id
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
  uri = aws_lambda_function.lambda_function_gettodos.invoke_arn
  ##. arn:aws:lambda:us-west-2:962804699607:function:grp3-cap2b-GetTodos
  depends_on = [
    aws_api_gateway_method.lambda_todo_api_get_method,
    aws_lambda_function.lambda_function_gettodos
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
    function_name = aws_lambda_function.lambda_function_gettodos.arn
    principal     = "apigateway.amazonaws.com"
    source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${aws_api_gateway_rest_api.lambda_todo_api.id}/*/${aws_api_gateway_method.lambda_todo_api_get_method.http_method}/*"
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
## CodeBuild Project (CodePipeline will have the webhook)
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
    # resources = ["arn:aws:ec2:us-west-2:123456789012:network-interface/*"]

    # condition {
    #   test     = "StringEquals"
    #   variable = "ec2:Subnet"

    #   values = [
    #     aws_subnet.example1.arn,
    #     aws_subnet.example2.arn,
    #   ]
    # }

    # condition {
    #   test     = "StringEquals"
    #   variable = "ec2:AuthorizedService"
    #   values   = ["codebuild.amazonaws.com"]
    # }
  }

  # statement {
  #   effect  = "Allow"
  #   actions = ["s3:*"]
  #   resources = [
  #     aws_s3_bucket.example.arn,
  #     "${aws_s3_bucket.example.arn}/*",
  #   ]
  # }
}

resource "aws_iam_role_policy" "code_build_policy" {
  role   = aws_iam_role.code_build_role.name
  policy = data.aws_iam_policy_document.policy_access.json
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

    # environment_variable {
    #   name  = "SOME_KEY1"
    #   value = "SOME_VALUE1"
    # }

    # environment_variable {
    #   name  = "SOME_KEY2"
    #   value = "SOME_VALUE2"
    #   type  = "PARAMETER_STORE"
    # }
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
## Create the CodePipeline and the webhook fo rit use for source changes
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

    # encryption_key {
    #   id   = data.aws_kms_alias.s3kmskey.arn
    #   type = "KMS"
    # }
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
        ClusterName    = "${var.group_alias}-cluster"
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
  name               = "test-role"
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume_role.json
}

data "aws_iam_policy_document" "codepipeline_policy" {
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

# data "aws_kms_alias" "s3kmskey" {
#   name = "alias/myKmsKey"
# }





##
##
## Add next:
##.  ECR Repository creation
##.  CodeBuild Project to build the Docker Image
##.  ECS Cluster
##.    ECS Cluster definition using Fargate
##.    Task Definition using ECR Repository Image
##.    Service Definition
##.    ALB to front-end the Service
##.  CopdePipeline:
##.    Source Action (retrieve GitHub source repo)
##.    CodeBuild Action (use SourceAction artifacts for build input, create imagedefinitions.json for ECS deployment as build artifact)
##.    CodeDeploy Action (use BuildAction artifacts for ECS deployment)
##
##
