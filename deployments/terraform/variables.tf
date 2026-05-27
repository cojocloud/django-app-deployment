variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "instance_ami" {
  description = "Ubuntu 22.04 AMI — update for your region"
  type        = string
  default     = "ami-0c7217cdde317cfec"
}

variable "key_name" {
  description = "EC2 Key Pair name (without .pem)"
  type        = string
  default     = "django-app-key"
}

variable "security_group_name" {
  type    = string
  default = "django-app-sg"
}
