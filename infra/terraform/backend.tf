terraform {
  # Update these values directly or pass -backend-config values to terraform init.
  backend "s3" {
    bucket         = "your-tf-state-bucket"
    key            = "ci-cd-project/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "your-tf-lock-table"
    encrypt        = true
  }
}
