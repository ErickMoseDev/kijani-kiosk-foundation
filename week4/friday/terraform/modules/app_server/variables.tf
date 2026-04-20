variable "name" {
  description = "Service name: api, payments, or logs"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch the instance into"
  type        = string
}



variable "ami_id" {
  description = "AMI ID to use for the instance"
  type        = string
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "vpc_id" {
  description = "Security group vpc id"
  type        = string

}

variable "my_ip_address" {
  description = "My current ip address"
  type        = string
}
