variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "eu-north-1"
}

variable "instance_type" {
  description = "EC2 instance type for bastion/test host"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of the EC2 key pair to use for SSH"
  type        = string
  default     = "demo-key" # must match the key pair you created in EC2 console
}

variable "my_ip_cidr" {
  description = "Your IP with /32 mask for SSH access (e.g., 1.2.3.4/32)"
  type        = string
}

variable "project_name" {
  description = "Short name for tagging and resource naming"
  type        = string
  default     = "demo"
}