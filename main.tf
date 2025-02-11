provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "custom_vpc" {
  cidr_block = "10.16.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "custom-vpc1"
  }
}

# IPv6 CIDR Block
resource "aws_vpc_cidr_block_association" "ipv6" {
  vpc_id = aws_vpc.custom_vpc.id
  amazon_provided_ipv6_cidr_block = true
}

# Internet Gateway
resource "aws_internet_gateway" "custom_igw" {
  vpc_id = aws_vpc.custom_vpc.id
  tags = {
    Name = "custom-vpc1-igw"
  }
}

# Route Tables and Associations
resource "aws_route_table" "web" {
  vpc_id = aws_vpc.custom_vpc.id
  tags = {
    Name = "custom-vpc1-rt-web"
  }
}

resource "aws_route" "default_ipv4" {
  route_table_id         = aws_route_table.web.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.custom_igw.id
}

resource "aws_route" "default_ipv6" {
  route_table_id              = aws_route_table.web.id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.custom_igw.id
}

resource "aws_route_table_association" "web_a" {
  subnet_id      = aws_subnet.web_a.id
  route_table_id = aws_route_table.web.id
}

# Subnets
resource "aws_subnet" "reserved_a" {
  vpc_id                  = aws_vpc.custom_vpc.id
  availability_zone        = data.aws_availability_zones.available.names[0]
  cidr_block              = "10.16.0.0/20"
  assign_ipv6_address_on_creation = true
  ipv6_cidr_block {
    cidr_block = "00::/64"
  }
  tags = {
    Name = "sn-reserved-A"
  }
}

# RDS DB Security Group
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.custom_vpc.id
  description = "Ingress control for RDS instance"
  ingress {
    description = "Allow MySQL IPv4 IN"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS DB Subnet Group
resource "aws_db_subnet_group" "db_subnet_group" {
  name        = "custom-db-subnet-group"
  description = "DB subnet group"
  subnet_ids  = [aws_subnet.reserved_a.id]
}

# RDS DB Instance
resource "aws_db_instance" "db" {
  allocated_storage    = 20
  db_instance_class    = "db.t3.micro"
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
  db_name             = var.db_name
  engine              = "mysql"
  engine_version      = var.db_version
  master_username     = var.db_user
  master_password     = var.db_password
  storage_type        = "gp3"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  tags = {
    Name = "CUSTOM-RDS-DB"
  }
}

# EC2 Security Group
resource "aws_security_group" "instance_sg" {
  vpc_id = aws_vpc.custom_vpc.id
  description = "Enable SSH and HTTP access"
  ingress {
    description = "Allow SSH IPv4 IN"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow HTTP IPv4 IN"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Role for EC2 Instance
resource "aws_iam_role" "ec2_instance_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# EC2 Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  role = aws_iam_role.ec2_instance_role.name
}

# EC2 Instance (for WordPress)
resource "aws_instance" "wordpress_instance" {
  ami             = var.latest_ami_id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.web_a.id
  security_groups = [aws_security_group.instance_sg.name]
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  tags = {
    Name = "wordpress-instance"
  }
}

# Variables (for DB)
variable "db_name" {
  type        = string
  default     = "dbname"
  description = "The database name"
}

variable "db_user" {
  type        = string
  default     = "dbuser"
  description = "The database admin account username"
}

variable "db_password" {
  type        = string
  default     = "dbpassword"
  description = "The database admin account password"
}

variable "db_version" {
  type        = string
  default     = "8.0.40"
  description = "The version of RDS"
}

variable "latest_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  description = "AMI for WordPress Instance"
}

