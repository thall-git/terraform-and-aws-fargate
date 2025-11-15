###############################################
# variables.tf
# ---------------------------------------------
# This file defines all user-configurable inputs
# for the Terraform project.
#
# Beginners often overlook that Terraform is
# intentionally designed to keep "settings" 
# separate from "infrastructure definitions".
#
# Each variable below can be overridden using:
#
#   terraform apply -var="variable_name=value"
#
# or by creating a terraform.tfvars file.
###############################################


############################################################
# enable_logging
#
# Type: bool (true/false)
# Default: false
#
# What it does:
# --------------
# Controls whether ECS task logs are sent to 
# AWS CloudWatch Logs.
#
# Why this matters:
# -----------------
# • CloudWatch logging is extremely useful for debugging.
# • But it costs money per GB ingested + stored.
# • Many people learning ECS/Fargate don’t need logs at first.
#
# When true:
#   - Terraform creates a CloudWatch Log Group
#   - The Fargate task sends stdout/stderr to CloudWatch
#
# When false:
#   - No Log Group is created
#   - No logConfiguration block is added to the container
############################################################
variable "enable_logging" {
  type    = bool
  default = false
}



############################################################
# aws_region
#
# Default: "us-east-1"
#
# What it does:
# --------------
# Specifies which AWS region Terraform should deploy into.
#
# Why this matters:
# -----------------
# • AWS has different Availability Zones in each region.
# • Prices vary by region.
# • Services available may vary slightly.
#
# IMPORTANT:
# ----------
# If you change the region, you *must* re-run:
#
#   terraform init
#
# because providers are region-specific.
############################################################
variable "aws_region" {
  default = "us-east-1"
}



############################################################
# project_name
#
# Default: "demo"
#
# What it does:
# --------------
# Provides a naming prefix for AWS resources created
# by this Terraform stack.
#
# Examples:
#   demo-alb
#   demo-tg-xxxx
#   demo-vpc
#   demo-service
#
# Why this matters:
# -----------------
# • Keeps related resources grouped together.
# • Makes cleanup easier.
# • Helps avoid AWS naming collisions.
#
# You should update this when:
# -----------------------------
# • Deploying multiple independent environments
# • Creating dev/staging/prod stacks
############################################################
variable "project_name" {
  default = "demo"
}



############################################################
# allowed_ingress_cidrs
#
# Type: list(string)
# Default: ["0.0.0.0/0"]
#
# What it does:
# --------------
# Defines which IP ranges are allowed to access the 
# public-facing Application Load Balancer.
#
# Why this matters:
# -----------------
# • "0.0.0.0/0" means *the entire world* can access it.
# • This is acceptable for examples/demos.
# • NOT acceptable in production.
#
# Beginner Notes:
# ---------------
# • CIDR stands for "Classless Inter-Domain Routing".
# • A CIDR like "203.0.113.5/32" means “only this one IP”.
#
# Production recommended examples:
# --------------------------------
# Allow only your office:
#   ["203.0.113.0/24"]
#
# Allow only your home IP:
#   ["198.51.100.42/32"]
#
# Allow multiple networks:
#   ["198.51.100.42/32", "203.0.113.0/24"]
############################################################
variable "allowed_ingress_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"] # Beginners: this allows the world (fine for demos)
}
