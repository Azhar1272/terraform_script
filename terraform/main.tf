provider "aws" {
    # Configuration supplied by Terraform Cloud environment variables
    #   region = "${var.region}"
#   // profile = "source"
  assume_role {
      role_arn = var.AWS_IAM_ROLE
  }

}




provider "snowflake" {
  account  = var.SNOWFLAKE_ACCOUNT
  username = var.SNOWFLAKE_USERNAME
  password = var.SNOWFLAKE_PASSWORD
  role     = var.SNOWFLAKE_ROLE
  # region   = var.SNOWFLAKE_REGION
}

terraform {
  required_providers {
    snowflake = {
          source = "Snowflake-Labs/snowflake"
          version = "0.58.2"
    }
    aws = {
      source = "hashicorp/aws"
      version = "4.59.0"
    }
  }
  # backend "remote" {
  #   hostname     = "app.terraform.io"
  #   organization = "lucion-group"

  #   workspaces {
  #     name = "NexGen-Terraform-Data"
  #   }
  # }
}


variable "ENV_NAME" {
  description = "Environment name (DEV or PROD)"
}
variable "AWS_IAM_ROLE" {
  description = "Environment name (DEV or PROD)"
}
variable "AWS_DEFAULT_REGION" {
  description = "AWS Default region"
}
variable "AWS_ACCESS_KEY_ID" {
  description = "AWS Secret Access Key"
}
variable "AWS_SECRET_ACCESS_KEY" {
  description = "AWS_SECRET_ACCESS_KEY"
}
variable "SNOWFLAKE_EXTERNAL_SQS_ARN" {
  description = "SNOWFLAKE_EXTERNAL_SQS_ARN"
}
