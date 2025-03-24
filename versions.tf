terraform {
  required_version = ">=1.9.2"

  required_providers {
    random = {
      source = "hashicorp/random"
      version = ">= 3.6.1"
    }
     aws = {
      source  = "hashicorp/aws"
      version = ">= 5.48.0"
    }
  }
}
