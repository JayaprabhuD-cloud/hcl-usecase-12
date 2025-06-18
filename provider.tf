terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "terraform-remote-state-bucket-s3-hcl"
    key    = "uc-11/terraform.tfstate"
    region = "ap-south-1"
    use_lockfile = true   
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-south-1"
}