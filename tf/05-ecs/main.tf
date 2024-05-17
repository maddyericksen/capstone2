##
## 05-ecs - main.tf
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
    key    = "state/remote-state-05-ecs"
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

provider "github" {
  token    = local.repo_cred
  owner    = "${var.repo_owner}"
  # base_url = "https://github.com/${var.repo_owner}/" # we have github enterprise
}


##
## Create the ECS Fargate cluster and service
##

##
## Retrieve information about the default VPC and Subnets and other references
##
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = "${data.aws_vpc.default.id}"
}

data "aws_ecr_repository" "todos_repo" {
  name = "${var.group_alias}-ecr"
}


## Define security groups for the ALB
resource "aws_security_group" "lb" {
  name        = "${var.group_alias}-alb-sg"
  description = "Controls access to the Application Load Balancer (ALB)"

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name     = "${var.group_alias}-alb-security-group"
    Capstone = "${var.group_alias}"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.group_alias}-ecs-tasks-sg"
  description = "Allow inbound access from the ALB only"

  ingress {
    protocol        = "tcp"
    from_port       = 3000
    to_port         = 3000
    cidr_blocks     = ["0.0.0.0/0"]
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name     = "${var.group_alias}-ecs-tasks-security-group"
    Capstone = "${var.group_alias}"
  }
}


##
## Create the ALB
##
resource "aws_lb" "todos_alb" {
  name               = "${var.group_alias}-ecs-alb"
  subnets            = data.aws_subnet_ids.default.ids
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]

  tags = {
    Name     = "${var.group_alias}-alb"
    Capstone = "${var.group_alias}"
    Application = "react-app"
  }
}

resource "aws_lb_listener" "todos_https_forward" {
  load_balancer_arn = aws_lb.todos_alb.arn
  port              = 80
  protocol          = "HTTP"

  tags = {
    Name     = "${var.group_alias}-alb-listener"
    Capstone = "${var.group_alias}"
    Application = "react-app"
  }

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.todos_tg.arn
  }
}

resource "aws_lb_target_group" "todos_tg" {
  name        = "${var.group_alias}-ecs-alb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  tags = {
    Name     = "${var.group_alias}-alb-targetgroup"
    Capstone = "${var.group_alias}"
    Application = "react-app"
  }

  health_check {
    healthy_threshold   = "3"
    interval            = "90"
    protocol            = "HTTP"
    matcher             = "200-299"
    timeout             = "20"
    path                = "/"
    unhealthy_threshold = "2"
  }
}


##
## Define IAM Role(s) for ECS
##
data "aws_iam_policy_document" "ecs_task_execution_role" {
  version = "2012-10-17"
  statement {
    sid     = ""
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.group_alias}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_role.json
  tags = {
    Name     = "${var.group_alias}-ecs-task-role"
    Capstone = "${var.group_alias}"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


##
## Create ECS Task Definition
##
resource "aws_ecs_task_definition" "task_def" {
  family                   = "${var.group_alias}-task-def"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  cpu                      = 1024
  memory                   = 3072
  requires_compatibilities = ["FARGATE"]
  container_definitions = jsonencode([
    {
      name = "react-app"
      image = "${aws_ecr_repository.todos_repo.url}:latest"
      cpu = 0
      portMappings = [
        {
          name = "react-app-3000-tcp"
          containerPort = 3000
          hostPort = 3000
          protocol = "tcp"
          appProtocol = "http"
        }
      ],
      essential = true
      environment = [
        {
          name = "PORT"
          value = "3000"
        }
      ]
      logConfiguration = {
          logDriver = "awslogs"
          options = {
              awslogs-create-group = true
              awslogs-group = "/ecs/${var.group_alias}-task-def"
              awslogs-region = "us-west-2"
              awslogs-stream-prefix = "ecs"
          }
      }
    }]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  tags = {
    Name     = "${var.group_alias}-task-def"
    Capstone = "${var.group_alias}"
    Application = "react-app"
  }
}


resource "aws_ecs_service" "todos_service" {
  name            = "staging"
  cluster         = aws_ecs_cluster.todos_cluster.id
  task_definition = aws_ecs_task_definition.taskdef.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = data.aws_subnet_ids.default.ids
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.todos_tg.arn
    container_name   = "react-app"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.todos_https_forward, aws_iam_role_policy_attachment.ecs_task_execution_role]

  tags = {
    Name     = "${var.group_alias}-task-def"
    Capstone = "${var.group_alias}"
    Application = "react-app"
  }
}






##
##
## Add next:
##.  ECS Cluster
##.    ECS Cluster definition using Fargate
##.    Task Definition using ECR Repository Image
##.    Service Definition
##.    ALB to front-end the Service
##
##
