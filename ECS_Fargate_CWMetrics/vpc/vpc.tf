# Configured within the provider
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  vpc_flow_log_group_name = "/aws/vpc/lab_vpc/flow-logs"
}

# Create VPC
resource "aws_vpc" "lab_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "lab_vpc"
  }
}

resource "aws_default_security_group" "lab_default" {
  vpc_id = aws_vpc.lab_vpc.id
}

resource "aws_kms_key" "vpc_flow_logs" {
  description             = "KMS key for lab VPC flow logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountAdministration"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogsUse"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.vpc_flow_log_group_name}"
          }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "vpc_flow_logs" {
  name          = "alias/lab-vpc-flow-logs"
  target_key_id = aws_kms_key.vpc_flow_logs.key_id
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = local.vpc_flow_log_group_name
  retention_in_days = 365
  kms_key_id        = aws_kms_key.vpc_flow_logs.arn
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "LabVpcFlowLogsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "LabVpcFlowLogsPolicy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "lab_vpc" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.lab_vpc.id
}

# Create Internet Gateway
resource "aws_internet_gateway" "lab_igw" {
  vpc_id = aws_vpc.lab_vpc.id
  tags = {
    Name = "lab_igw"
  }
}

# Create public subnet in AZ-a
resource "aws_subnet" "lab_pub1_subnet" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${data.aws_region.current.name}a"
  tags = {
    Name = "lab_pub1_subnet"
  }
}

# Create public subnet in AZ-b
resource "aws_subnet" "lab_pub2_subnet" {
  vpc_id            = aws_vpc.lab_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${data.aws_region.current.name}b"
  tags = {
    Name = "lab_pub1_subnet"
  }
}

# Create public route table & Attach Internet Gateway
resource "aws_route_table" "lab_pub_rtb" {
  vpc_id = aws_vpc.lab_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab_igw.id
  }
  tags = {
    Name = "lab_pub_rtb"
  }
}

# Associate public subnet to public route table
resource "aws_route_table_association" "public_subnet1_assoc" {
  subnet_id      = aws_subnet.lab_pub1_subnet.id
  route_table_id = aws_route_table.lab_pub_rtb.id
}

resource "aws_route_table_association" "public_subnet2_assoc" {
  subnet_id      = aws_subnet.lab_pub2_subnet.id
  route_table_id = aws_route_table.lab_pub_rtb.id
}


# Outputs
output "public_subnet_1_id" {
  value = aws_subnet.lab_pub1_subnet.id
}

output "public_subnet_2_id" {
  value = aws_subnet.lab_pub2_subnet.id
}

output "vpc" {
  value = aws_vpc.lab_vpc.id
}
