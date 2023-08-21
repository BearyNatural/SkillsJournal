# Base & Start
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-southeast-2"  # ap-southeast-2 
  alias  = "SYD"
  default_tags {
    tags = {
      deployed_by = "BearyNatural"
    }
  }
}

# Configured within the provider
data "aws_region" "current" {}
data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

# 1. Import VPC module
module "vpc" {
  source = "./vpc/"
}

# 2. Import ECR module
module "ecr" {
  depends_on = [ module.vpc ]
  source = "./ecr/"
}

# 3. Import EC2 module
module "ec2" {
  depends_on = [ module.ecr, module.vpc ]
  source = "./ec2/"
  repourl = module.ecr.repo_url
  repoarn = module.ecr.repo_arn
  reponame = module.ecr.repo_name
  region = data.aws_region.current.name
  vpc        = module.vpc.vpc
  subnetid   = module.vpc.public_subnet_1_id
  accountid  = data.aws_caller_identity.current.account_id
}

# 4. Import ECS module
module "ecs_fargate" {
  depends_on = [module.vpc, module.ecr, module.ec2]
  source     = "./ecs_fargate/"
  subnet1    = module.vpc.public_subnet_1_id
  subnet2    = module.vpc.public_subnet_2_id
  repourl    = module.ecr.repo_url
  vpc        = module.vpc.vpc
  region     = data.aws_region.current.name
}

