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


data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# locals
locals {
  servers = {
    api = {
      instance_type = "${var.instance_type}"
      port          = 3000
    }
    payments = {
      instance_type = "${var.instance_type}"
      port          = 3001
    }
    logs = {
      instance_type = "${var.instance_type}"
      port          = 5000
    }
  }
}

# reference the data block inside a resource
module "api_servers" {
  source        = "./modules/app_server"
  for_each      = local.servers
  name          = each.key
  instance_type = each.value.instance_type
  environment   = var.environment
  ami_id        = data.aws_ami.ubuntu24.id
  subnet_id     = data.aws_subnets.default.ids[0]
  vpc_id        = data.aws_vpc.default.id
  key_name      = var.ssh_key_name
  my_ip_address = var.my_ip_address

}

