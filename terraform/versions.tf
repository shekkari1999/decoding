# Tell Terraform which Terraform CLI and provider versions this project supports.
terraform {
  # Require a modern Terraform version that understands this configuration.
  required_version = ">= 1.6.0"

  # Declare every external provider used by this configuration.
  required_providers {
    # Use the official AWS provider to create EC2 resources.
    aws = {
      # Download the provider from HashiCorp's official registry namespace.
      source = "hashicorp/aws"
      # Allow compatible releases in the current major version.
      version = "~> 6.0"
    }
  }
}

# Configure the AWS provider with the region supplied in terraform.tfvars.
provider "aws" {
  # Create every resource in the selected AWS region.
  region = var.aws_region
}
