terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Bucket/table names come from `terraform/bootstrap`'s output - fill these
  # in after running bootstrap once (terraform init doesn't support variable
  # interpolation in the backend block).
  backend "s3" {
    bucket         = "beantrack-tfstate-126862223873"
    key            = "shared/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "beantrack-tfstate-lock"
    encrypt        = true
  }
}
