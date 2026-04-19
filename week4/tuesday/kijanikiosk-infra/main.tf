terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
# Configure the AWS Provider
provider "aws" {
  region = var.region
}

# configure data source to lookup the ubuntu 24 ami dynamically
# documentation reference: https://developer.hashicorp.com/terraform/tutorials/aws-get-started/aws-manage
data "aws_ami" "ubuntu24" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's AWS account Id

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# TODO: add a security group or firewall rule block that allows:
# - SSH (22) from your IP only
# - HTTP (80) from anywhere
# - All outbound traffic

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "web_sg" {
  description = "Allow SSH from my IP, HTTP from anywhere, all outbound"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_address]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# reference the data block inside a resource
resource "aws_instance" "kk_api" {
  ami                    = data.aws_ami.ubuntu24.id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  tags = {
    Name        = var.instance_name
    Environment = var.environment
    Owner       = var.owner
  }

}
