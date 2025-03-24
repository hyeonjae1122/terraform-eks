# This file is used to configure the backend for Terraform.
# If you are using a local backend, you can use the following configuration:
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }

## If you are using S3 as a backend, you can use the following configuration:
terraform {
  backend "s3" {
    bucket = "YOUR BUCKET NAME"   # S3 Bucket Name
    key    = "terraform.tfstate"  # S3 Path
    region = "ap-northeast-2"   # S3 Region
    encrypt = true                    # Enable Server-Side Encryption
  }
}