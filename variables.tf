variable "eks_version" {
  type = string
  description = "The EKS version to use"
}

variable "vpc_cidr" {
  type = string
  description = "The CIDR block for the VPC"
}

variable "secondary_cidr_blocks" {
  type = list(string)
  description = "The secondary CIDR blocks for the VPC"
}

variable "name_prefix" {
    type = string
    description = "The prefix to use for all resources"  
}

variable "region" {
    type = string
    description = "The region to deploy to"
  
}