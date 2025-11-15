###############################################################################
# main.tf — Fully Documented AWS Fargate + ALB Example
#
# This file builds a complete AWS architecture using Terraform:
#
#   - VPC with two public subnets
#   - Internet Gateway + route tables
#   - Security groups for ALB + ECS tasks
#   - Application Load Balancer (ALB)
#   - ECS Cluster (Fargate)
#   - Fargate Task Definition (nginx)
#   - ECS Service running behind the ALB
#   - Auto Scaling (CPU + ALB Request Count)
#   - Optional CloudWatch Logs
#
# Every major block includes detailed explanations so beginners can learn
# exactly how AWS + Terraform + ECS Fargate work together.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

###############################
# Provider
###############################
provider "aws" {
  region = var.aws_region
}

###############################################################################
# VPC — Virtual Private Cloud
#
# A VPC is your own isolated private network inside AWS. Every AWS compute
# resource (ECS, EC2, RDS, Lambda ENIs, etc.) must live inside a VPC.
#
# We create a large /16 network (10.0.0.0 – 10.0.255.255) so we have plenty
# of address space for subnets, tasks, ALBs, and future expansion.
###############################################################################
resource "aws_vpc" "demo" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "demo-vpc"
  }
}

###############################################################################
# Subnets (Public)
#
# These two subnets live in different availability zones.
# They are "public" because:
#   - They automatically assign public IPs on launch
#   - Their route table points to an Internet Gateway
#
# Fargate tasks placed in these subnets receive:
#   - A private IP inside the VPC
#   - A public IP for internet access (assign_public_ip = true)
###############################################################################
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.demo.id

  # cidrsubnet() divides 10.0.0.0/16 into smaller subnets
  cidr_block              = cidrsubnet(aws_vpc.demo.cidr_block, 4, count.index)

  # Spread subnets across AZs for high availability
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  # Allow ECS tasks to automatically receive public IPs
  map_public_ip_on_launch = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

###############################################################################
# Internet Gateway — Allows the VPC to communicate with the internet
###############################################################################
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.demo.id
}

###############################################################################
# Route Table — Sends 0.0.0.0/0 traffic to the Internet Gateway
###############################################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

###############################################################################
# Associate each public subnet with the public route table
###############################################################################
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

################################################################################
# Security Group for the ALB
#
# This SG:
#   - Allows HTTP (80) from anyone on the internet
#   - Allows all outbound traffic
################################################################################
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.demo.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

################################################################################
# Security Group for Fargate Tasks
#
# Only allows inbound traffic from the ALB security group.
################################################################################
resource "aws_security_group" "ecs_sg" {
  name   = "ecs-sg"
  vpc_id = aws_vpc.demo.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

################################################################################
# Application Load Balancer
#
# ALB distributes HTTP traffic across multiple ECS tasks.
################################################################################
resource "aws_lb" "demo" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

################################################################################
# Target Group
#
# target_type = "ip" is REQUIRED for Fargate. The ALB will forward
# requests directly to the Elastic Network Interface of each task.
################################################################################
resource "aws_lb_target_group" "demo" {
  name        = "${var.project_name}-tg-${random_string.suffix.result}"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.demo.id

  health_check {
    path = "/"
  }
}

resource "random_string" "suffix" {
  length  = 4
  special = false
}

################################################################################
# Listener — Listens on port 80 and forwards to the target group
################################################################################
resource "aws_lb_listener" "demo" {
  load_balancer_arn = aws_lb.demo.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo.arn
  }
}

################################################################################
# ECS Cluster — A logical grouping of ECS tasks/services
################################################################################
resource "aws_ecs_cluster" "demo" {
  name = "demo-ecs"
}

################################################################################
# Task Definition (Fargate)
#
# This is the "virtual machine template" for ECS. A task is one running copy
# of this definition.
#
# CPU = 256 = 0.25 vCPU on Fargate
# Memory = 512 MB
################################################################################
resource "aws_ecs_task_definition" "demo" {
  family                   = "demo-nginx"
  network_mode             = "awsvpc"  # required for Fargate
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512

  execution_role_arn = aws_iam_role.ecs_task_exec.arn

  container_definitions = jsonencode([
    {
      name  = "nginx"
      image = "nginx:latest"

      # Expose container port 80
      portMappings = [{
        containerPort = 80
        protocol      = "tcp"
      }]

      # Optional CloudWatch Logging
      logConfiguration = var.enable_logging ? {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/demo-nginx"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      } : null

      ##########################################################################
      # Startup Command
      #
      # Runs nginx and dynamically writes:
      #   - Task ID
      #   - Private IP
      #   - Metadata URI
      ##########################################################################
      command = [
        "bash",
        "-c",
        <<-EOT
          set -e

          META_URI="$${ECS_CONTAINER_METADATA_URI_V4}"

          apt-get update >/dev/null 2>&1 || true
          apt-get install -y curl jq >/dev/null 2>&1 || true

          TASK_ID=""
          TASK_IP=""

          if [ -n "$${ECS_CONTAINER_METADATA_URI_V4}" ]; then
            JSON=$(curl -s "$${ECS_CONTAINER_METADATA_URI_V4}" || true)
            if [ -n "$JSON" ]; then
              TASK_ID=$(echo "$JSON" | jq -r '.DockerId' | cut -c1-12 || true)
              TASK_IP=$(echo "$JSON" | jq -r '.Networks[0].IPv4Addresses[0]' || true)
            fi
          fi

          {
            echo "<h1>Hello from Fargate!</h1>"
            echo "<p>TASK_ID: $${TASK_ID}</p>"
            echo "<p>Private IP: $${TASK_IP}</p>"
            echo "<p>META_URI: $${META_URI}</p>"
          } > /usr/share/nginx/html/index.html

          nginx -g 'daemon off;'
        EOT
      ]
    }
  ])
}

################################################################################
# ECS Service — Runs and maintains tasks
#
# - desired_count = 1 (autoscaling overrides this)
# - ALB attached
# - Fargate networking with public IP auto-assigned
################################################################################
resource "aws_ecs_service" "demo" {
  name            = "demo-service"
  cluster         = aws_ecs_cluster.demo.id
  task_definition = aws_ecs_task_definition.demo.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.demo.arn
    container_name   = "nginx"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.demo
  ]
}

################################################################################
# Auto Scaling Target (required before policies)
#
# Tells AWS we want to auto-scale ECS service desired count.
################################################################################
resource "aws_appautoscaling_target" "ecs_scaling_target" {
  max_capacity       = 5
  min_capacity       = 1

  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.demo.name}/${aws_ecs_service.demo.name}"
}

################################################################################
# Auto Scaling Policy #1 — Scale based on ALB Requests per Target
################################################################################
resource "aws_appautoscaling_policy" "ecs_alb_requests_policy" {
  name               = "ecs-alb-req-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label = "${aws_lb.demo.arn_suffix}/${aws_lb_target_group.demo.arn_suffix}"
    }

    # If >100 requests/sec per task → scale out
    target_value       = 100
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

################################################################################
# Auto Scaling Policy #2 — Scale based on CPU Utilization
################################################################################
resource "aws_appautoscaling_policy" "ecs_cpu_policy" {
  name               = "ecs-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 60  # If CPU >60% for sustained period → scale out
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

################################################################################
# IAM Role — Allows Fargate tasks to pull Docker images & use logs
################################################################################
resource "aws_iam_role" "ecs_task_exec" {
  name = "ecsTaskExecutionRole-demo"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_policy" {
  role       = aws_iam_role.ecs_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

################################################################################
# CloudWatch Log Group (Optional)
################################################################################
resource "aws_cloudwatch_log_group" "ecs" {
  count             = var.enable_logging ? 1 : 0
  name              = "/ecs/demo-nginx"
  retention_in_days = 7
}
