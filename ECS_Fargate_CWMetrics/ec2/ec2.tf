# Create the security group for the instance that creates the image
resource "aws_security_group" "allow_all" {
  name        = "allow_all_ec2"
  description = "Allow all inbound traffic" # cut this later to least priv
  vpc_id      = var.vpc

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Fetch the latest Amazon Linux 2 AMI
data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

# Fetch the current spot price for the desired instance type
data "aws_ec2_spot_price" "spot_price" {
  instance_type     = var.instancetype
  availability_zone = "${var.region}a" 
  filter {
    name   = "product-description"
    values = ["Linux/UNIX"]
  }
}

# Calculate a bid price that is 10% over the current spot price
locals {
  bid_price = format("%.4f", (1 + 0.10) * tonumber(data.aws_ec2_spot_price.spot_price.spot_price))
}

# Create the Spot instance for Docker image creation
resource "aws_spot_instance_request" "docker_image_builder" {
  ami                  = data.aws_ssm_parameter.ami.value
  instance_type        = var.instancetype
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  security_groups      = [aws_security_group.allow_all.id]
  subnet_id            = var.subnetid
  spot_type            = "one-time"

  spot_price           = local.bid_price
  wait_for_fulfillment = true

  instance_initiated_shutdown_behavior = "terminate"

  root_block_device {
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl",
    {
      dockerfile = file("${path.module}/../container/Dockerfile"),
      app        = file("${path.module}/../container/app.py"),
      region     = var.region
      repourl    = var.repourl
      reponame   = var.reponame
      accountid  = var.accountid
    }
    )
  )

  tags = {
    Name = "DockerBuilder"
  }
}