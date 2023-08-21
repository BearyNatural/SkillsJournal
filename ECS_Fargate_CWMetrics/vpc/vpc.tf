# Configured within the provider
data "aws_region" "current" {}

# Create VPC
resource "aws_vpc" "lab_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "lab_vpc"
  }
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
  vpc_id     = aws_vpc.lab_vpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true # if you want instances in this subnet to get public ips
  availability_zone = "${data.aws_region.current.name}a"
  tags = {
    Name = "lab_pub1_subnet"
  }
}

# Create public subnet in AZ-b
resource "aws_subnet" "lab_pub2_subnet" {
  vpc_id     = aws_vpc.lab_vpc.id
  cidr_block = "10.0.2.0/24"
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
  subnet_id = aws_subnet.lab_pub1_subnet.id
  route_table_id = aws_route_table.lab_pub_rtb.id
}

resource "aws_route_table_association" "public_subnet2_assoc" {
  subnet_id = aws_subnet.lab_pub2_subnet.id
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