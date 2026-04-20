variable "region" {
  description = "The region where the EC2 instance will be provisioned"
  type        = string
  default     = "af-south-1"
}

variable "instance_type" {
  description = "The hardware profile of the provisioned VM"
  type        = string
  default     = "t3.micro"
}

variable "ssh_key_name" {
  description = "My configured ssh key name"
  type        = string
}

variable "my_ip_address" {
  description = "My current ip address"
  type        = string
}

variable "instance_name" {
  description = "The name of the VM"
  type        = string
  default     = "kk_api"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "staging"
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be staging or production."
  }
}

variable "owner" {
  description = "Owner of the resource"
  type        = string
}
