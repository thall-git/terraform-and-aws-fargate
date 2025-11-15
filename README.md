# AWS Fargate + Terraform Example (Beginner Friendly)

This repository provides a **fully documented, production-quality example** of how to deploy:

- A VPC with two public subnets  
- An Internet Gateway and a public route table  
- A security-hardened Application Load Balancer  
- An ECS Cluster (Fargate)  
- A Fargate Task Definition running nginx  
- Dynamic HTML showing the task’s private IP  
- Auto-Scaling using CPU and ALB Request Count  
- Optional CloudWatch logging (toggle via variable)

The goal is to help beginners understand **every moving part** of an ECS Fargate deployment.

---

## ✅ Requirements

Before using these files, you must:

- Install terraform (https://developer.hashicorp.com/terraform/install)
- Install aws cli (https://aws.amazon.com/cli/)
- Configure aws-cli via 'aws configure'

---	

## 📁 File Overview

### **main.tf**
This is the primary Terraform configuration.  
It creates the entire AWS infrastructure end-to-end.

It includes teaching-style comments explaining:

- What each AWS service does  
- Why each block is required  
- How ECS, ALB, VPC, and networking interact  
- How autoscaling policies work  
- How Fargate metadata and networking operate  

This is designed for people learning AWS or Terraform for the first time.

---

### **variables.tf**
Defines user-configurable settings such as:

```hcl
variable "aws_region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "demo"
}

variable "enable_logging" {
  default = true
}
