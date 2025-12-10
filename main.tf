provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "example_bucket" {
  bucket = "cortex-demo-insecure-bucket"
  # Intentional Security Flaws:
  # 1. No encryption defined
  # 2. No access logging defined
  # 3. Public access blocks not strictly enforced
}