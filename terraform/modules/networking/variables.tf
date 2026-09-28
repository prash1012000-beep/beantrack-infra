variable "name" {
  type        = string
  description = "Prefix for all resource names, e.g. \"beantrack\"."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.20.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones to spread subnets across. Two is enough for an ALB and RDS multi-AZ."
}
